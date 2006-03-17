#!/usr/bin/perl

# TODO: ignore the "     " spaces in between end/start events?  used as keep-alive
#
# TODO: server to server... port 5269

use strict;
use Carp;
use Danga::Socket 1.49;
use IO::Socket::INET;
use POSIX ();

use DJabberd::Callback;
use Scalar::Util;
use DJabberd::Connection;
use DJabberd::Connection::ServerIn;
use DJabberd::Connection::ClientIn;

use DJabberd::Stanza::StartTLS;
use DJabberd::Stanza::StreamFeatures;
use DJabberd::Stanza::DialbackVerify;
use DJabberd::Stanza::DialbackResult;
use DJabberd::JID;
use DJabberd::IQ;
use DJabberd::Message;
use DJabberd::Presence;
use DJabberd::StreamVersion;

package DJabberd;
use strict;
use Socket qw(IPPROTO_TCP TCP_NODELAY SOL_SOCKET SOCK_STREAM);

sub new {
    my ($class, %opts) = @_;

    my $self = {
        'server_name' => delete $opts{server_name},
        'daemonize'   => delete $opts{daemonize},
        'auth_hooks'  => delete $opts{auth_hooks},
        's2s'         => delete $opts{s2s},
        'hooks'       => {},
    };

    my $plugins = delete $opts{plugins};
    die "unknown opts" if %opts; #FIXME: better

    bless $self, $class;

    warn "Addding plugins...\n";
    foreach my $pl (@{ $plugins || [] }) {
        warn "  ... adding plugin: $pl\n";
        $self->add_plugin($pl);
    }

    return $self;
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

sub add_plugin {
    my ($self, $plugin) = @_;
    $plugin->register($self);
}

sub register_hook {
    my ($self, $phase, $subref) = @_;
    # TODO: die if bogus phase
    push @{ $self->{hooks}{$phase} ||= [] }, $subref;
}

# local connections
my %jid2sock;  # bob@207.7.148.210/rez -> DJabberd::Connection
               # bob@207.7.148.210     -> DJabberd::Connection

sub find_jid {
    my ($class, $jid) = @_;
    if (ref $jid) {
        return $class->find_jid($jid->as_string) ||
               $class->find_jid($jid->as_bare_string);
    }
    my $sock = $jid2sock{$jid} or return undef;
    return undef if $sock->{closed};
    return $sock;
}

sub register_jid {
    my ($class, $jid, $sock) = @_;
    warn "REGISTERING $jid  ==> $sock\n";
    $jid2sock{$jid->as_string}      = $sock;
    $jid2sock{$jid->as_bare_string} = $sock;
}

# returns true if given jid is recognized as "for the server"
sub uses_jid {
    my ($self, $jid) = @_;
    return 0 unless $jid;
    # FIXME: this does no canonicalization of server_name, for one
    return $jid->as_string eq $self->{server_name};
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
    $self->start_s2s_server() if $self->{s2s};

    Danga::Socket->EventLoop();
}

sub start_c2s_server {
    my $self = shift;

    # establish SERVER socket, bind and listen.
    my $server = IO::Socket::INET->new(LocalPort => 5222,  # {=clientportnumber}
                                       Type      => SOCK_STREAM,
                                       Proto     => IPPROTO_TCP,
                                       Blocking  => 0,
                                       Reuse     => 1,
                                       Listen    => 10 )
        or die "Error creating socket: $@\n";

    warn "file of c2s = ", fileno($server), "\n";

    # Not sure if I'm crazy or not, but I can't see in strace where/how
    # Perl 5.6 sets blocking to 0 without this.  In Perl 5.8, IO::Socket::INET
    # obviously sets it from watching strace.
    IO::Handle::blocking($server, 0);

    my $accept_handler = sub {
        my $csock = $server->accept();
        return unless $csock;

        $self->debug("Listen child making a DJabberd::Connection for %d.\n", fileno($csock));

        IO::Handle::blocking($csock, 0);
        setsockopt($csock, IPPROTO_TCP, TCP_NODELAY, pack("l", 1)) or die;

        my $client = DJabberd::Connection::ClientIn->new($csock, $self);
        $client->watch_read(1);
    };

    Danga::Socket->AddOtherFds(fileno($server) => $accept_handler);
}

sub start_s2s_server {
    my $self = shift;

    # establish SERVER socket, bind and listen.
    my $server = IO::Socket::INET->new(LocalPort => 5269,  # {=serverportnumber}
                                       Type      => SOCK_STREAM,
                                       Proto     => IPPROTO_TCP,
                                       Blocking  => 0,
                                       Reuse     => 1,
                                       Listen    => 10 )
        or die "Error creating socket: $@\n";

    warn "file of s2s = ", fileno($server), "\n";

    # Not sure if I'm crazy or not, but I can't see in strace where/how
    # Perl 5.6 sets blocking to 0 without this.  In Perl 5.8, IO::Socket::INET
    # obviously sets it from watching strace.
    IO::Handle::blocking($server, 0);

    my $accept_handler = sub {
        my $csock = $server->accept();
        return unless $csock;

        $self->debug("Listen child making a DJabberd::Connection for %d.\n", fileno($csock));

        IO::Handle::blocking($csock, 0);
        setsockopt($csock, IPPROTO_TCP, TCP_NODELAY, pack("l", 1)) or die;

        my $client = DJabberd::Connection::ServerIn->new($csock, $self);
        $client->watch_read(1);
    };

    Danga::Socket->AddOtherFds(fileno($server) => $accept_handler);
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
