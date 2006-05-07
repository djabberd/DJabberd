package DJabberd::Plugin;
use strict;
use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

sub new {
    my $class = shift;
    return bless {}, $class;
}

# called when </Plugin> line is parsed.  you can die here if the object hasn't
# been setup properly
sub finalize {
}

# list of classnames you want to run before/after (in your phase only)
sub run_after {
    return ()
}

sub run_before {
    return ()
}

sub register {
    my ($self, $server) = @_;
    $logger->warn("[not implemented] $self should register for $server");
}

1;
