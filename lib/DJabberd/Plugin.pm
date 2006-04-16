package DJabberd::Plugin;
use strict;
use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

sub register {
    my ($self, $server) = @_;
    $logger->warn("[not implemented] $self should register for $server");
}

1;
