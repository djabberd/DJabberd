package DJabberd::Message;
use strict;
use base qw(DJabberd::XMLElement);

sub to {
    return $_[0]->attr("{jabber:client}to");
}

sub from {
    return $_[0]->attr("{jabber:client}from");
}

1;
