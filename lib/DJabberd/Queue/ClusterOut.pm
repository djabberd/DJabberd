package DJabberd::Queue::ClusterOut;
use strict;
use warnings;
use base 'DJabberd::Queue';
use DJabberd::Connection::ClusterOut;

use DJabberd::Log;

our $logger = DJabberd::Log->get_logger;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    $self->{endpt}    = delete $opts{endpoint} or die "endpoint required";
    $self->{vhost}    = delete $opts{vhost}  or die "vhost required";
    Carp::croak("Not a vhost: $self->{vhost}") unless $self->vhost->isa("DJabberd::VHost");
    die "too many opts" if %opts;

    $self->{to_deliver} = [];  # DJabberd::QueueItem?
    $self->{last_connect_fail} = 0;  # unixtime of last connection failure

    $self->{state} = NO_CONN;   # see states above

    $logger->debug("Creating new server out queue for vhost '" . $self->{vhost}->name . "' to domain '$self->{domain}'.");

    return $self;
}


1;

