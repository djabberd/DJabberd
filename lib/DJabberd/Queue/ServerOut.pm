package DJabberd::Queue::ServerOut;
use strict;
use warnings;
use DJabberd::Connection::ServerOut;

use constant NO_CONN    => \ "no connection";
use constant RESOLVING  => \ "resolving";
use constant CONNECTING => \ "connecting";
use constant CONNECTED  => \ "connected";

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    $self->{del_source} = delete $opts{source} or die "delivery 'source' required";
    $self->{domain}     = delete $opts{domain} or die "domain required";
    $self->{vhost}      = delete $opts{vhost}  or die "vhost required";
    die "too many opts" if %opts;

    $self->{to_deliver} = [];  # DJabberd::QueueItem?
    $self->{last_connect_fail} = 0;  # unixtime of last connection failure

    $self->{state} = NO_CONN;   # see states above

    return $self;
}

# called by Connection::ServerOut constructor
sub set_connection {
    my ($self, $conn) = @_;
    warn "$self connection set to $conn ...\n";
    $self->{connection} = $conn;
}

sub vhost {
    my $self = shift;
    return $self->{vhost};
}

sub domain {
    my $self = shift;
    return $self->{domain};
}

sub queue_stanza {
    my ($self, $stanza, $cb) = @_;

    if ($self->{state} == NO_CONN) {
        $self->start_connecting;
    }

    if ($self->{state} == CONNECTED) {
        $self->{connection}->send_stanza($stanza);
        $cb->delivered;
    } else {
        push @{ $self->{to_deliver} }, DJabberd::QueueItem->new($stanza, $cb);
    }
}

sub failed_to_connect {
    my $self = shift;
    $self->{state}             = NO_CONN;
    $self->{last_connect_fail} = time();

    while (my $qi = shift @{ $self->{to_deliver} }) {
        $qi->callback->fail;
    }
}

# called by our connection when it's connected
sub on_connection_connected {
    my ($self, $conn) = @_;
    warn "connection connected!  from ($self)1  conn=$conn, selfcon=$self->{connection}\n";
    return unless $conn == $self->{connection};
    warn "connection connected!  from ($self)2\n";

    $self->{state} = CONNECTED;
    while (my $qi = shift @{ $self->{to_deliver} }) {
        $conn->send_stanza($qi->stanza);
        $qi->callback->delivered;
    }
}

sub on_connection_failed {
   my ($self, $conn) = @_;
   return unless $conn == $self->{connection};
   return $self->failed_to_connect;
}

sub on_connection_error {
   my ($self, $conn) = @_;
   return unless $conn == $self->{connection};
   my $pre_state = $self->{state};

   $self->{state}      = NO_CONN;
   $self->{connection} = undef;

   if ($pre_state == CONNECTING) {
       # died while connecting:  no more luck
       warn "Connection error while connecting, giving up.\n";
       while (my $qi = shift @{ $self->{to_deliver} }) {
           $qi->callback->error("connection failure");
       }
   } else {
       # died during an active connection, let's try again
       if (@{ $self->{to_deliver} }) {
           warn "Reconnecting on $self\n";
           $self->start_connecting;
       }
   }
}

sub start_connecting {
    my $self = shift;
    die unless $self->{state} == NO_CONN;

    # TODO: moratorium/exponential backoff on attempting to deliver to
    # something that's recently failed to connect.  instead, immediately
    # call ->failed_to_connect without even trying.

    $self->{state} = RESOLVING;

    # async DNS lookup
    DJabberd::DNS->srv(service  => "_xmpp-server._tcp",
                       domain   => $self->{domain},
                       callback => sub {
                           my @ips = @_;
                           unless (@ips) {
                               $self->failed_to_connect;
                               return;
                           }

                           my $ip = shift @ips;
                           # FIXME: include port numbers
                           $self->{state} = CONNECTING;
                           my $conn = DJabberd::Connection::ServerOut->new(ip => $ip, queue => $self);
                           $self->set_connection($conn);
                           $conn->start_connecting;
                       });
}

package DJabberd::QueueItem;

sub new {
    my ($class, $stanza, $cb) = @_;
    return bless [ $stanza, $cb ], $class;
}

sub stanza   { return $_[0][0] }
sub callback { return $_[0][1] }


1;

