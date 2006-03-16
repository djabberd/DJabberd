package DJabberd::Presence;
use strict;
use base qw(DJabberd::Stanza);

sub process {
    my ($self, $conn) = @_;
    warn "$self ->process not implemented\n";
}


1;
