# outgoing connection to another server in our domain
package DJabberd::Connection::ClusterOut;
use strict;
use base 'DJabberd::Connection::ServerOut';
use Carp qw(croak);

sub on_connected {
    my $self = shift;
    # TODO:
    #   start binary protocol

}

sub event_read {
    # ... read binary protocol
}

1;
