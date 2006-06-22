package DJabberd::Queue;

use strict;
use warnings;

use base 'Exporter';

our @EXPORT_OK = qw(NO_CONN RESOLVING CONNECTING CONNECTED);

use DJabberd::Log;

our $logger = DJabberd::Log->get_logger;

use fields (
	    'vhost',
	    'endpoints',
	    'to_deliver',
	    'last_connect_fail',
	    'state',
	    'connection',
	    );

use constant NO_CONN    => \ "no connection";
use constant RESOLVING  => \ "resolving";
use constant CONNECTING => \ "connecting";
use constant CONNECTED  => \ "connected";

sub new {
    my $self = shift;
    my %opts = @_;

    $self = fields::new($self) unless ref $self;

    $self->{vhost}      = delete $opts{vhost}  or die "vhost required";
    Carp::croak("Not a vhost: $self->{vhost}") unless $self->vhost->isa("DJabberd::VHost");

    if (my $endpoints = delete $opts{endpoints}) {
	Carp::croak("endpoints must be an arrayref") unless (ref $endpoints eq 'ARRAY');
	  $self->{endpoints} = $endpoints;
      } else {
	  $self->{endpoints} = [];
      }

    die "too many opts" if %opts;

    $self->{to_deliver} = [];  # DJabberd::QueueItem?
    $self->{last_connect_fail} = 0;  # unixtime of last connection failure

    $self->{state} = NO_CONN;   # see states above

    return $self;
}

sub endpoints {
    my $self = shift;
    my $endpoints = $self->{endpoints};

    if (@_) {
	@$endpoints = @_;
    }
    return @$endpoints;
}

# called by Connection::ServerOut constructor
sub set_connection {
    my ($self, $conn) = @_;
    $logger->debug("Set connection for queue to '$self->{domain}' to connection '$conn->{id}'");
    $self->{connection} = $conn;
}

sub vhost {
    my $self = shift;
    return $self->{vhost};
}

sub enqueue {
    my ($self, $stanza, $cb) = @_;

    $logger->debug("Queuing stanza (" . $stanza . ") for");

    if ($self->{state} == NO_CONN) {
        $logger->debug("  .. starting to connect to");
        $self->start_connecting;
    }

    if ($self->{state} == CONNECTED) {
        $logger->debug("  .. already connected, writing stanza.");
        $self->{connection}->send_stanza($stanza);
        $cb->delivered;
    } else {
        $logger->debug("  .. pushing queue item.");
        push @{ $self->{to_deliver} }, DJabberd::QueueItem->new($stanza, $cb);
    }
}

sub failed_to_connect {
    my $self = shift;
    $self->{state}             = NO_CONN;
    $self->{last_connect_fail} = time();

    $logger->debug("Failed to connect queue");
    while (my $qi = shift @{ $self->{to_deliver} }) {
        $qi->callback->error;
    }
}

# called by our connection when it's connected
sub on_connection_connected {
    my ($self, $conn) = @_;
    $logger->debug("connection $conn->{id} connected!  conn=$conn->{id}, selfcon=$self->{connection}->{id}");

    # TODO why are we this checking here?
    return unless $conn == $self->{connection};

    $logger->debug(" ... unloading queue items");
    $self->{state} = CONNECTED;
    while (my $qi = shift @{ $self->{to_deliver} }) {
        $conn->send_stanza($qi->stanza);
        $qi->callback->delivered;
	# TODO: the connection might need to handle marking things as delivered
	# otherwise we could run into a problem if the connection dies mid-stanza.
    }
}

sub on_connection_failed {
   my ($self, $conn) = @_;
   $logger->debug("connection failed for queue");
   return unless $conn == $self->{connection};
   $logger->debug("  .. match");
   return $self->failed_to_connect;
}

sub on_connection_error {
   my ($self, $conn) = @_;
   $logger->debug("connection error for queue");
   return unless $conn == $self->{connection};
   $logger->debug("  .. match");
   my $pre_state = $self->{state};

   $self->{state}      = NO_CONN;
   $self->{connection} = undef;

   if ($pre_state == CONNECTING) {
       # died while connecting:  no more luck
       $logger->error("Connection error while connecting, giving up");
       $self->on_final_error;
   } else {
       # died during an active connection, let's try again
       if (@{ $self->{to_deliver} }) {
           $logger->warn("Reconnecting to '$self->{domain}'");
           $self->start_connecting;
       }
   }
}

sub on_final_error {
    my $self = shift;
    while (my $qi = shift @{ $self->{to_deliver} }) {
        $qi->callback->error("connection failure");
    }
}

sub start_connecting {
    my $self = shift;
    $logger->debug("Starting connection");
    die unless $self->{state} == NO_CONN;

    my $endpoints = $self->{endpoints};

    unless (@$endpoints) {
	$self->failed_to_connect;
	return;
    }

    $self->{state} = CONNECTING;

    my $endpt = $endpoints->[0];
    my $conn = $self->new_connection(endpoint => $endpt, queue => $self);
    $self->set_connection($conn);
    $conn->start_connecting;

}

sub new_connection {
    die "Sorry, this method needs to be overridden in your subclass of " . ref( $_[0] ) . ".";
}

package DJabberd::QueueItem;

sub new {
    my ($class, $stanza, $cb) = @_;
    return bless [ $stanza, $cb ], $class;
}

sub stanza   { return $_[0][0] }
sub callback { return $_[0][1] }

1;
