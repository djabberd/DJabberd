package DJabberd::Queue::ClusterOut;
use strict;
use warnings;
use base 'DJabberd::Queue';
use DJabberd::Queue qw();
use DJabberd::Connection::ClusterOut;

use DJabberd::Log;

our $logger = DJabberd::Log->get_logger;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    $self->{endpt}    = delete $opts{endpoint} or die "endpoint required";
    $self->{vhost}    = delete $opts{vhost}  or die "vhost required";
    $logger->debug("Creating new server out queue for vhost '" . $self->{vhost}->name . "' to domain '$self->{domain}'.");

    return $self;
}


1;

