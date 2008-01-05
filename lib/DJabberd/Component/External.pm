
=head1 NAME

DJabberd::Component::External - Interface to external plugins implementing JEP-0114

=head1 DESCRIPTION

This component provides support for connecting external components that support the
Jabber Component Protocol specified in JEP-0114. Specify the TCP port that the external component
will connect on and the secret it will use to authenticate. These should match the equivilent
settings in the component's own configuration.

You can also specify a ListenAddr option, which specifies the IP address of the interface to
listen on. By default, we only listen on the loopback address, 127.0.0.1. Alternatively,
you can give a UNIX domain socket (an absolute path beginning with a slash) and leave out
the ListenPort setting to await a connection on a UNIX domain socket. Most components do not
support UNIX domain sockets, however.

Please note that this component only implements the "accept" variation of the protocol,
where DJabberd opens a listen socket and waits for the component to connect. The "connect"
variation, where the component waits for DJabberd to connect to it, is not supported.

=head1 SYNOPSIS

  <Plugin DJabberd::Component::External>
    ListenPort 23534
    Secret somesecret
  </Plugin>

=head1 LICENCE

Copyright 2006 Martin Atkins and Six Apart

This library is part of the Jabber server DJabberd. It can be modified and distributed
under the same terms as DJabberd itself.

=cut

package DJabberd::Component::External;

use base 'DJabberd::Component';
use strict;
use DJabberd::Log;
use DJabberd::Util qw(exml);
use DJabberd::Connection::ComponentIn;
use IO::Socket::UNIX;
use IO::Socket::INET;
use Socket qw(IPPROTO_TCP TCP_NODELAY SOL_SOCKET SOCK_STREAM);

our $logger = DJabberd::Log->get_logger();

sub set_config_listenport {
    my ($self, $port) = @_;
    
    return $self->set_config_listenaddr($port);
}

sub set_config_secret {
    my ($self, $secret) = @_;
    
    $self->{secret} = $secret;
}

sub set_config_listenaddr {
    my ($self, $addr) = @_;
    
    $self->{listenaddr} = DJabberd::Util::as_bind_addr($addr);
}

sub finalize {
    my ($self) = @_;
    
    $logger->logdie("No ListenPort specified for external component") unless $self->{listenaddr};
    $self->{listenaddr} = "127.0.0.1:".$self->{listenaddr} if $self->{listenaddr} =~ /^\d+$/;

    $logger->logdie("No Secret specified for external component") unless $self->{secret};
    
    $self->SUPER::finalize;
}

sub register {
    my ($self, $vhost) = @_;
    
    $self->SUPER::register($vhost);

    $self->_start_listener();

}

sub secret {
    return $_[0]->{secret};
}

sub handle_component_disconnect {
    my ($self, $connection) = @_;
    
    if ($connection != $self->{connection}) {
        $logger->warn("Got disconnection for the wrong connection. Something's screwy.");
        return 0;
    }

    $logger->info("Component ".$self->domain." disconnected.");

    $self->{connection} = undef;
    $self->_start_listener();  # Re-open the listen port so the component can re-connect.
    return 1;
}

# Stanza from the server to the component
sub handle_stanza {
    my ($self, $vhost, $stanza) = @_;
    
    # If the component is not connected, return Service Unavailable
    unless ($self->{connection} && $self->{connection}->is_authenticated) {
        $stanza->make_error_response('503', 'cancel', 'service-unavailable')->deliver($vhost);
        return;
    }
    
    $self->{connection}->send_stanza($stanza);
}

# Stanza from the component to the server
sub handle_component_stanza {
    my ($self, $stanza) = @_;
    
    if ($stanza->from_jid && $stanza->from_jid->domain eq $self->domain) {
        $stanza->deliver($self->vhost);
    }
    else {
        $logger->warn("External component ".$self->domain." used bogus from address. Discarding stanza.");
    }
}

sub _start_listener {
    my ($self) = @_;
    my $vhost = $self->vhost;
    
    my $bindaddr = $self->{listenaddr};

    # FIXME: Maybe shouldn't duplicate all of this code out of DJabberd.pm.
    
    my $server;
    my $not_tcp = 0;
    if ($bindaddr =~ m!^/!) {
        $not_tcp = 1;
        $server = IO::Socket::UNIX->new(
            Type   => SOCK_STREAM,
            Local  => $bindaddr,
            Listen => 10
        );
        $logger->logdie("Error creating UNIX domain socket $bindaddr: $@") unless $server;
        $logger->info("Started listener for component ".$self->domain." on UNIX domain socket $bindaddr");
    } else {
        $server = IO::Socket::INET->new(
            LocalAddr => $bindaddr,
            Type      => SOCK_STREAM,
            Proto     => IPPROTO_TCP,
            Blocking  => 0,
            Reuse     => 1,
            Listen    => 10
        );
        $logger->logdie("Error creating listen socket for <$bindaddr>: $@") unless $server;
        $logger->info("Started listener for component ".$self->domain." on TCP socket <$bindaddr>");
    }

    # Brad thinks this is necessary under Perl 5.6, and who am I to argue?
    IO::Handle::blocking($server, 0);
    
    $self->{listener} = $server;

    my $accept_handler = sub {
        my $csock = $server->accept;
        return unless $csock;
        
        $logger->debug("Accepting connection from component ".$self->domain);

        IO::Handle::blocking($csock, 0);
        unless ($not_tcp) {
            setsockopt($csock, IPPROTO_TCP, TCP_NODELAY, pack("l", 1)) or $logger->logdie("Couldn't set TCP_NODELAY");
        }

        my $connection = DJabberd::Connection::ComponentIn->new($csock, $vhost->server, $self);
        $connection->watch_read(1);
        $self->{connection} = $connection;

        # We only need to support one connection at a time, so
        # shut down the listen socket now to save resources.
        $self->_stop_listener($self);
    };
    
    Danga::Socket->AddOtherFds(fileno($server) => $accept_handler);
}

sub _stop_listener {
    my ($self) = @_;
    
    return unless $self->{listener};
    $logger->info("Shutting down listener for component ".$self->domain);
    $self->{listener} = undef if $self->{listener}->close();
    return $self->{listener} == undef;
}

1;
