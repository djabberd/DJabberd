package DJabberd::Stanza;
use strict;
use base qw(DJabberd::XMLElement);

sub process {
    my $self = shift;
    die "Stanza->process not implemented for $self\n";
}

1;
