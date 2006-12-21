
=head1 NAME

DJabberd::Delivery::ComponentConnection - Delivery through a JEP-0114 component connection

=head1 INTRODUCTION

This class allows you to route stanzas over a JEP-0114 component connection. It can operate
both as a server (to which you can connect third-party JEP-0114 components) and as a client,
where a DJabberd VHost itself acts as a component.

The server support allows you to connect third-party components and transports such as
the popular pyXXXt range of transports to other IM networks.

The client support means that you can expose any DJabberd VHost as a JEP-0114 component
and connect the resulting component to any other Jabberd implementation which supports
JEP-0114. In effect this allows you to use DJabberd as a platform to write a component while
retaining your existing Jabber server implementation.

Note: The server mode doesn't currently work. See DJabberd::Component::External.
This module may change name at some point; the combination of the client and server modes into
on module is not finalized.

=head1 LICENCE

Copyright 2006 Martin Atkins and Six Apart

This library is part of the Jabber server DJabberd. It can be modified and distributed
under the same terms as DJabberd itself.

=cut

package DJabberd::Delivery::ComponentConnection;

use strict;
use base qw(DJabberd::Delivery);
use DJabberd::Connection::ComponentOut;
use DJabberd::DNS;
use Socket qw(PF_INET IPPROTO_TCP SOCK_STREAM TCP_NODELAY);

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

    $addr = DJabberd::Util::as_bind_addr($addr);
    
    my ($ipaddr, $port) = split(/:/, $addr);

    unless (defined($port)) {
        $port = $ipaddr;
        $ipaddr = "127.0.0.1";
    }

    $self->{listenaddr} = $ipaddr;
    $self->{listenport} = $port;
    
}

sub set_config_remoteaddr {
    my ($self, $addr) = @_;

    # TODO: Make this support DNS lookups later
    $addr = DJabberd::Util::as_bind_addr($addr);

    my ($ipaddr, $port) = split(/:/, $addr);

    unless (defined($port)) {
        $port = $ipaddr;
        $ipaddr = "127.0.0.1";
    }
    
    $self->{remoteaddr} = $ipaddr;
    $self->{remoteport} = $port;

}

sub finalize {
    my ($self) = @_;

    $logger->logdie("Must specify either ListenAddr (to connect an external component) or RemoteAddr (to expose this vhost as a component)") unless $self->{listenaddr} || $self->{remoteaddr};
    
    $self->{i_am_the_component} = $self->{remoteaddr} ? 1 : 0;

    $logger->logdie("No Secret specified for component") unless $self->{secret};
    
    my $dispaddr = $self->{i_am_the_component} ? $self->{remoteaddr}.":".$self->{remoteport} : $self->{listenaddr}.":".$self->{listenport};
    $logger->debug("I'm running in ".($self->{i_am_the_component} ? "client" : "server")." mode and using ".$dispaddr);
    
    $self->SUPER::finalize;
}

sub register {
    my ($self, $vhost) = @_;
    
    $self->SUPER::register($vhost);

    $self->_prepare_connection();
}

sub deliver {
    my ($self, $vhost, $cb, $stanza) = @_;

    if ($self->_can_deliver_stanza($stanza)) {
        if (my $conn = $self->connection) {
            $conn->write_stanza($stanza);
        }
        else {
            # If we've currently got no connection at all,
            # let's throw a wobbly.
            # FIXME: Could this get into an infinite loop in some cases? Probably.
            $stanza->make_error_response('503', 'cancel', 'service-unavailable')->deliver($vhost);
        }
        return $cb->delivered;
    }
    else {
        return $cb->decline;
    }

}

sub _i_am_the_component {
    return $_[0]->{i_am_the_component};
}

sub _can_deliver_stanza {
    my ($self, $stanza) = @_;
    
    # If we're the component, we want to offload anything with a domain
    # other than our own. If we aren't the component, the reverse is true.
    my $same_host = ($stanza->to_jid->domain eq $self->vhost->server_name);
    
    return $self->_i_am_the_component ? ! $same_host : $same_host;
}

sub connection {
    return $_[0]->{connection};
}

sub _prepare_connection {
    my ($self) = @_;
    
    if ($self->_i_am_the_component) {
        $self->_start_connection($self);
    }
    else {
        $self->_start_listener($self);
    }
}

sub _start_connection {
    my ($self) = @_;
    
    my $vhost = $self->vhost;
    
    my $connection = DJabberd::Connection::ComponentOut->new(
        endpoint => DJabberd::IPEndPoint->new($self->{remoteaddr}, $self->{remoteport}),
        vhost => $vhost,
        secret => $self->{secret},
    );
    $connection->watch_read(1);
    $connection->add_connect_handler(sub {
        $logger->debug("Connection established and channel open.");
        $self->{connection} = $connection;
    });
    $connection->add_disconnect_handler(sub {
        # FIXME: Maybe this delay should get exponentially longer each retry?
        # We're probably only connecting to localhost anyway, so I shant bother for now.
        $logger->debug("Outgoing connection was lost. Will attempt to re-establish it in 30 seconds.");

        Danga::Socket->AddTimer(30, sub {
            $self->{connection} = undef;
            $self->_prepare_connection();
        });
    });

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
