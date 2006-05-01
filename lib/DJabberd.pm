#!/usr/bin/perl

use strict;
use Carp;
use Danga::Socket 1.51;
use IO::Socket::INET;
use POSIX ();

use DJabberd::Callback;
use Scalar::Util;
use DJabberd::HookDocs;
use DJabberd::Connection;
use DJabberd::Connection::ServerIn;
use DJabberd::Connection::ClientIn;
use DJabberd::Connection::OldSSLClientIn;

use DJabberd::Stanza::StartTLS;
use DJabberd::Stanza::StreamFeatures;
use DJabberd::Stanza::DialbackVerify;
use DJabberd::Stanza::DialbackResult;
use DJabberd::JID;
use DJabberd::IQ;
use DJabberd::Message;
use DJabberd::Presence;
use DJabberd::StreamVersion;
use DJabberd::Log;
package DJabberd;
use strict;
use Socket qw(IPPROTO_TCP TCP_NODELAY SOL_SOCKET SOCK_STREAM);
use Carp qw(croak);
use DJabberd::Util qw(tsub);

our $logger = DJabberd::Log->get_logger();
our $hook_logger = DJabberd::Log->get_logger("DJabberd::Hook");

sub new {
    my ($class, %opts) = @_;

    my $self = {
        'server_name' => delete $opts{server_name},
        'daemonize'   => delete $opts{daemonize},
        's2s'         => delete $opts{s2s},
        'c2s_port'    => delete($opts{c2s_port}) || 5222,
        'old_ssl'     => delete $opts{old_ssl},
        'require_ssl' => delete $opts{require_ssl},
        'hooks'       => {},
    };

    my $plugins = delete $opts{plugins};
    die "unknown opts" if %opts; #FIXME: better

    bless $self, $class;

    $logger->info("Addding plugins...");
    foreach my $pl (@{ $plugins || [] }) {
        $logger->info("  ... adding plugin: $pl");
        $self->add_plugin($pl);
    }

    return $self;
}

sub run_hook_chain {
    my $self = shift;
    my %opts = @_;

    my $phase    = delete $opts{'phase'};
    my $methods  = delete $opts{'methods'} || {};
    my $args     = delete $opts{'args'}    || [];
    my $fallback = delete $opts{'fallback'};
    die if %opts;

    # make phase into an arrayref;
    $phase = [ $phase ] unless ref $phase;

    my @hooks;
    foreach my $ph (@$phase) {
        $logger->logcroak("Undocumented hook phase: '$ph'") unless
            $DJabberd::HookDocs::hook{$ph};
        push @hooks, @{ $self->{hooks}->{$ph} || [] };
    }
    push @hooks, $fallback if $fallback;

    my $try_another;
    my $stopper = tsub {
        $try_another = undef;
    };
    $try_another = tsub {

        my $hk = shift @hooks
            or return;

        $hk->($self,
              DJabberd::Callback->new(
                                      decline    => $try_another,
                                      declined   => $try_another,
                                      stop_chain => $stopper,
                                      _post_fire => sub {
                                          # when somebody fires this callback, we know
                                          # we're done (unless it was decline/declined)
                                          # and we need to clean up circular references
                                          my $fired = shift;
                                          unless ($fired =~ /^decline/) {
                                              $try_another = undef;
                                          }
                                      },
                                      %$methods,
                                      ),
              @$args);
    };

    $try_another->();
}

# return the version of the spec we implement
sub spec_version {
    my $self = shift;
    return $self->{_spec_version} ||= DJabberd::StreamVersion->new("1.0");
}

sub name {
    my $self = shift;
    return $self->{server_name} || die "No server name configured.";
    # FIXME: try to determine it
}

# vhost method
sub add_plugin {
    my ($self, $plugin) = @_;
    $plugin->register($self);
}

*requires_ssl = \&require_ssl;  # english
sub require_ssl {
    my $self = shift;
    return $self->{require_ssl};
}

sub are_hooks {
    my ($self, $phase) = @_;
    return scalar @{ $self->{hooks}{$phase} || [] } ? 1 : 0;
}

sub register_hook {
    my ($self, $phase, $subref) = @_;
    # TODO: die if bogus phase
    push @{ $self->{hooks}{$phase} ||= [] }, $subref;
}

# local connections
my %jid2sock;  # bob@207.7.148.210/rez -> DJabberd::Connection
               # bob@207.7.148.210     -> DJabberd::Connection
my %bare2fulls; # barejids -> { fulljid -> 1 }

sub find_jid {
    my ($self, $jid) = @_;
    if (ref $jid) {
        return $self->find_jid($jid->as_string) ||
               $self->find_jid($jid->as_bare_string);
    }
    my $sock = $jid2sock{$jid} or return undef;
    return undef if $sock->{closed};
    return $sock;
}

sub register_jid {
    my ($self, $jid, $sock) = @_;
    $logger->info("Registering '$jid' to connection '$sock->{id}'");

    my $barestr = $jid->as_bare_string;
    my $fullstr = $jid->as_string;
    $jid2sock{$fullstr} = $sock;
    $jid2sock{$barestr} = $sock;
    ($bare2fulls{$barestr} ||= {})->{$fullstr} = 1;
}

# given a bare jid, find all local connections
sub find_conns_of_bare {
    my ($self, $jid) = @_;
    my $barestr = $jid->as_bare_string;
    my @conns;
    foreach my $fullstr (keys %{ $bare2fulls{$barestr} || {} }) {
        my $conn = $self->find_jid($fullstr)
            or next;
        push @conns, $conn;
    }

    return @conns;
}

# returns true if given jid is recognized as "for the server"
sub uses_jid {
    my ($self, $jid) = @_;
    return 0 unless $jid;
    # FIXME: this does no canonicalization of server_name, for one
    return $jid->as_string eq $self->{server_name};
}

# returns true if given jid is controlled by this vhost
sub handles_jid {
    my ($self, $jid) = @_;
    return 0 unless $jid;
    # FIXME: this does no canonicalization of server_name, for one
    return $jid->domain eq $self->{server_name};
}

sub roster_push {
    my ($self, $jid, $ritem) = @_;

    # FIXME: single-server roster push only.   need to use a hook
    # to go across the cluster

    my $xml = "<query xmlns='jabber:iq:roster'>";
    $xml .= $ritem->as_xml;
    $xml .= "</query>";

    my @conns = $self->find_conns_of_bare($jid);
    foreach my $c (@conns) {
        #TODO:  next unless $c->is_available;
        my $id = $c->new_iq_id;
        my $iq = "<iq to='" . $c->bound_jid->as_string . "' type='set' id='$id'>$xml</iq>";
        $c->xmllog->info($iq);
        $c->write(\$iq);
    }
}

my %obj_source;   # refaddr -> file/linenumber
my %obj_living;   # file/linenumber -> ct
use Scalar::Util qw(refaddr weaken);
use Data::Dumper;
sub dump_obj_stats {
    print Dumper(\%obj_living);
    my %class_ct;
    foreach (values %obj_source) {
        $class_ct{ref($_->[1])}++;
    }
    print Dumper(\%class_ct);
}

sub track_new_obj {
    my ($class, $obj) = @_;
    my $i = 0;
    my $fileline;
    while (!$fileline) {
        $i++;
        my ($pkg, $filename, $line, $subname) = caller($i);
        next if $subname eq "new";
        $fileline = "$filename/$line";
    }
    my $addr = refaddr($obj);
    warn "New object $obj -- $fileline\n" if $ENV{TRACKOBJ};
    $obj_source{$addr} = [$fileline, $obj];
    weaken($obj_source{$addr}[1]);

    $obj_living{$fileline}++;
    dump_obj_stats() if $ENV{TRACKOBJ};
}

sub track_destroyed_obj {
    my ($class, $obj) = @_;
    my $addr = refaddr($obj);
    my $fileline = $obj_source{$addr}->[0] or die "Where did $obj come from?";
    delete $obj_source{$addr};
    warn "Destroyed object $obj -- $fileline\n" if $ENV{TRACKOBJ};
    $obj_living{$fileline}--;
    dump_obj_stats() if $ENV{TRACKOBJ};
}

sub debug {
    my $self = shift;
    return unless $self->{debug};
    printf STDERR @_;
}

sub run {
    my $self = shift;
    daemonize() if $self->{daemonize};
    local $SIG{'PIPE'} = "IGNORE";  # handled manually

    $self->start_c2s_server();

    # {=s2soptional}
    $self->start_s2s_server() if $self->{s2s};

    Danga::Socket->EventLoop();
}

sub _start_server {
    my ($self, $port, $class) = @_;

    # establish SERVER socket, bind and listen.
    my $server = IO::Socket::INET->new(LocalPort => $port,
                                       Type      => SOCK_STREAM,
                                       Proto     => IPPROTO_TCP,
                                       Blocking  => 0,
                                       Reuse     => 1,
                                       Listen    => 10 )
        or die "Error creating socket: $@\n";

    # Not sure if I'm crazy or not, but I can't see in strace where/how
    # Perl 5.6 sets blocking to 0 without this.  In Perl 5.8, IO::Socket::INET
    # obviously sets it from watching strace.
    IO::Handle::blocking($server, 0);

    my $accept_handler = sub {
        my $csock = $server->accept;
        return unless $csock;

        $self->debug("Listen child making a DJabberd::Connection for %d.\n", fileno($csock));

        IO::Handle::blocking($csock, 0);
        setsockopt($csock, IPPROTO_TCP, TCP_NODELAY, pack("l", 1)) or die;

        my $client = $class->new($csock, $self);
        $client->watch_read(1);
    };

    Danga::Socket->AddOtherFds(fileno($server) => $accept_handler);
}

sub start_c2s_server {
    my $self = shift;
    $self->_start_server(5222,  # {=clientportnumber}
                         "DJabberd::Connection::ClientIn");

    if ($self->{old_ssl}) {
        $self->_start_server(5223, "DJabberd::Connection::OldSSLClientIn");
    }
}

sub start_s2s_server {
    my $self = shift;
    $self->_start_server(5269,  # {=serverportnumber}
                         "DJabberd::Connection::ServerIn");
}

sub start_simple_server {
    my ($self, $port) = @_;
    eval "use DJabberd::Connection::SimpleIn; 1"
        or die "Failed to load DJabberd::Connection::SimpleIn: $@\n";
    $self->_start_server($port, "DJabberd::Connection::SimpleIn");
}

sub daemonize {
    my($pid, $sess_id, $i);

    ## Fork and exit parent
    if ($pid = fork) { exit 0; }

    ## Detach ourselves from the terminal
    Carp::croak("Cannot detach from controlling terminal")
        unless $sess_id = POSIX::setsid();

    ## Prevent possibility of acquiring a controling terminal
    $SIG{'HUP'} = 'IGNORE';
    if ($pid = fork) { exit 0; }

    ## Change working directory
    chdir "/";

    ## Clear file creation mask
    umask 0;

    ## Close open file descriptors
    close(STDIN);
    close(STDOUT);
    close(STDERR);

    ## Reopen stderr, stdout, stdin to /dev/null
    open(STDIN,  "+>/dev/null");
    open(STDOUT, "+>&STDIN");
    open(STDERR, "+>&STDIN");
}

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

1;
