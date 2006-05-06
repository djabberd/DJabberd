#!/usr/bin/perl

use strict;
use Carp;
use Danga::Socket 1.51;
use IO::Socket::INET;
use POSIX ();
use XML::SAX::Expat;

use DJabberd::VHost;
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

use DJabberd::Delivery::Local;
use DJabberd::Delivery::S2S;
use DJabberd::PresenceChecker::Local;


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
        'daemonize'   => delete $opts{daemonize},
        's2s_port'    => delete $opts{s2s_port},
        'c2s_port'    => delete($opts{c2s_port}) || 5222, # {=clientportnumber}
        'old_ssl'     => delete $opts{old_ssl},
        'vhosts'      => {},
    };

    # if they set s2s_port to explicitly 0, it's disabled for all vhosts
    # but not setting it means 5269 still listens, if vhosts are configured
    # for s2s.
    # {=serverportnumber}
    $self->{s2s_port} = 5269 unless defined $self->{s2s_port};

    die "unknown opts" if %opts; #FIXME: better

    bless $self, $class;
    return $self;
}

sub add_vhost {
    my ($self, $vhost) = @_;
    my $sname = $vhost->name;
    if (my $existing = $self->{vhosts}{$sname}) {
        croak("Can't set vhost with name '$sname'.  Already exists in this server.")
            if $existing != $vhost;
    }
    if ($vhost->server && $vhost->server != $self) {
        croak("Vhost already has a server.");
    }

    $self->{vhosts}{$sname} = $vhost;
    $vhost->set_server($self);
}

sub lookup_vhost {
    my ($self, $hostname) = @_;
    return $self->{vhosts}{lc $hostname};
}

# return the version of the spec we implement
sub spec_version {
    my $self = shift;
    return $self->{_spec_version} ||= DJabberd::StreamVersion->new("1.0");
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
    $self->start_s2s_server() if $self->{s2s_port};

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
    $self->_start_server($self->{c2s_port},
                         "DJabberd::Connection::ClientIn");

    if ($self->{old_ssl}) {
        $self->_start_server(5223, "DJabberd::Connection::OldSSLClientIn");
    }
}

sub start_s2s_server {
    my $self = shift;
    $self->_start_server($self->{s2s_port},
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
