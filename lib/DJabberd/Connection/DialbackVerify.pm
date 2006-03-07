# outgoing connection to another server for the sole purpose of verifying a dialback result.
package DJabberd::Connection::DialbackVerify;
use strict;
use base 'DJabberd::Connection';

# ... TODO: connect out, call callbacks, etc.
#

sub start_stream {
    my DJabberd::Connection $self = shift;

    return;
}

1;
