package DJabberd::Message;
use strict;
use base qw(DJabberd::Stanza);

sub process {
    my ($self, $conn) = @_;
    $conn->process_message($self);
}

sub to {
    return $_[0]->attr("{jabber:client}to");
}

sub from {
    return $_[0]->attr("{jabber:client}from");
}

1;
