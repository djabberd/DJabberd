package DJabberd::Stanza;
use strict;
use base qw(DJabberd::XMLElement);

sub process {
    my ($self, $conn) = @_;
    $self->route(source => $conn);
}

sub route {
    my ($self, %opts) = @_;
    my $src = delete $opts{'source'};
    die if %opts;



}

sub process {
    my $self = shift;
    die "Stanza->process not implemented for $self\n";
}

1;
