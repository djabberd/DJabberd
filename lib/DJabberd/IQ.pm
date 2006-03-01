package DJabberd::IQ;
use strict;
use base qw(DJabberd::XMLElement);

sub id {
    return $_[0]->attr("{jabber:client}id");
}

sub type {
    return $_[0]->attr("{jabber:client}type");
}

sub query {
    my $self = shift;
    my $child = $self->first_element
        or return;
    my $ele = $child->element
        or return;
    return undef unless $child->element =~ /\}query$/;
    return $child;
}

1;
