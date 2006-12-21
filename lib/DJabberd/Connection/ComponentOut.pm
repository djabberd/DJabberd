
=head1 NAME

DJabberd::Connection::ComponentOut - JEP-0114 Client

=head1 INTRODUCTION

This class provides the "client" end (the initiating party) of a JEP-0114 Component Protocol
connection.

=head1 LICENCE

Copyright 2006 Martin Atkins and Six Apart

This library is part of the Jabber server DJabberd. It can be modified and distributed
under the same terms as DJabberd itself.

=cut

package DJabberd::Connection::ComponentOut;
use strict;
use base 'DJabberd::Connection';
use DJabberd::Log;
use Digest::SHA1;
use Socket qw(PF_INET IPPROTO_TCP SOCK_STREAM);

our $logger = DJabberd::Log->get_logger();

use fields (
    'state',           # Connection state ('disconnected', 'connecting', 'connected')
    'authenticated',   # Whether we have completed the authentication handshake (boolean)
    'secret',          # The secret used in the handshake with the server (a string)
    'connect_handlers',  # array of coderefs to call when this connection is established
);

sub new {
    my ($class, %opts) = @_;
    
    my $endpoint = delete($opts{endpoint}) or $logger->logdie("No endpoint specified");
    my $vhost = delete($opts{vhost}) or $logger->logdie("No vhost specified");
    my $secret = delete($opts{secret}) || ""; # FIXME: The secret can't currently be the number 0 :)
    $logger->logdie("Invalid options ".join(',',keys %opts)) if %opts;
    
    $logger->warning("No shared secret specified for component connection in $vhost") unless $secret;
    
    my $server = $vhost->server;

    $logger->debug("Making a $class connecting to ".$endpoint->addr.":".$endpoint->port);
    
    my $sock;
    socket $sock, PF_INET, SOCK_STREAM, IPPROTO_TCP;
    unless ($sock && defined fileno($sock)) {
        $logger->logdie("Failed to allocate socket");
        return;
    }
    IO::Handle::blocking($sock, 0) or $logger->logdie("Failed to make socket non-blocking");
    connect $sock, Socket::sockaddr_in($endpoint->port, Socket::inet_aton($endpoint->addr));
    
    my $self = $class->SUPER::new($sock, $server);
    $self->watch_write(1);

    $self->set_vhost($vhost);
    $self->{secret} = $secret;
    $self->{authenticated} = 0;
    $self->{state} = 'connecting';
    
    #$self->{cmpnt_handler} = $handler;
    #Scalar::Util::weaken($self->{cmpnt_handler});

    $logger->debug("$class initialized");
    
    return $self;
}

sub on_connected {
    my ($self) = @_;
    my $vhost = $self->{vhost};

    $logger->debug("Got connection");

    # JEP-0114 stipulates that we must put our server name
    # in the "to" attribute. Some other components, notably the
    # pyXXXt family of transports, seem to use the 'from' attribute
    # instead, so maybe this will have to change when talking
    # to some server implementations. We'll see.
    $self->start_init_stream(to => $vhost->server_name, xmlns => $self->namespace);
    $self->watch_read(1);
    $self->_run_callback_list($self->{connect_handlers});
}

sub event_write {
    my $self = shift;

    if ($self->{state} eq "connecting") {
        $self->{state} = "connected";
        $self->on_connected;
    } else {
        return $self->SUPER::event_write;
    }
}

sub namespace {
    return "jabber:component:accept";
}

sub on_stream_start {
    my DJabberd::Connection::ComponentOut $self = shift;
    my $ss = shift;
    return $self->close unless $ss->xmlns eq $self->namespace; # FIXME: should be stream error

    # Once we get to this point, we've connected to the server, we've sent our <stream>
    # open tag and then this callback tells us we've got the server's <stream> open tag.
    # Now we need to send our handshake based on the id attribute the server has given us.

    $logger->debug("Got stream start for server ".$ss->to);

    $self->{in_stream} = 1;

    my $correct_domain = $self->{vhost}->server_name;

    my $stream_id = $ss->id;
    my $handshake = lc(Digest::SHA1::sha1_hex($stream_id.$self->{secret}));

    $logger->debug("I'm sending a handshake of $handshake based on a stream id of ".$stream_id." and the configured secret");

    $self->write('<handshake>'.$handshake.'</handshake>');
}

sub is_server { 1 }

sub is_authenticated {
    return $_[0]->{authenticated};
}

my %element2class = (
    "{jabber:component:accept}iq"       => 'DJabberd::IQ',
    "{jabber:component:accept}message"  => 'DJabberd::Message',
    "{jabber:component:accept}presence" => 'DJabberd::Presence',
);

sub on_stanza_received {
    my ($self, $node) = @_;

    if ($self->xmllog->is_info) {
        $self->log_incoming_data($node);
    }

    unless ($self->{authenticated}) {
        my $type = $node->element;
        
        if ($type eq '{urn:ietf:params:xml:ns:xmpp-tls}starttls') {
            my $stanza = DJabberd::Stanza::StartTLS->downbless($node, $self);
            $stanza->process($self);
            return;
        }
        
        unless ($type eq '{jabber:component:accept}handshake') {
            $logger->warn("Server sent $type stanza before handshake acknowledgement. Discarding.");
            return;
        }
        
        # Server sends us a handshake element (rather than a stream error)
        # to indicate success. The contents are irrelevent.
        
        $logger->debug("Handshake accepted. We are now authenticated.");
        $self->{authenticated} = 1;
        
        return;
    }

    my $class = $element2class{$node->element} or return $self->stream_error("unsupported-stanza-type");

    # same variable as $node, but down(specific)-classed.
    my $stanza = $class->downbless($node, $self);

    # at present, there are no filter hooks for component connections
    # we assume that components trust their server.
    # Also, we just pretent we're S2S here for hook purposes since we basically are,
    # and S2S and Component delivery are mutually exclusive anyway.

    $self->vhost->run_hook_chain(phase => "switch_incoming_server",
                          args  => [ $stanza ],
                          methods => {
                              process => sub { $stanza->process($self) },
                              deliver => sub { $stanza->deliver($self) },
                          },
                          fallback => sub {
                              $stanza->on_recv_from_server($self);
                          });
}


sub add_connect_handler {
    my ($self, $callback) = @_;
    $self->{connect_handlers} ||= [];
    push @{$self->{connect_handlers}}, $callback;
}

1;
