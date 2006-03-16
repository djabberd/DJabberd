package DJabberd::Message;
use strict;
use base qw(DJabberd::Stanza);

sub process {
    my ($self, $conn) = @_;

    die "Can't process a to-server message?";
}

1;
