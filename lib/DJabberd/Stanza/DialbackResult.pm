package DJabberd::Stanza::DialbackResult;
use strict;
use base qw(DJabberd::Stanza);

use DJabberd::Connection::DialbackVerify;

sub process {
    my ($self, $conn) = @_;

    #....
    my $verify_conn = DJabberd::Connection::DialbackVerify->new();

    #....

}

1;
