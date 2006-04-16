package DJabberd::Stanza::DialbackVerify;
# remote servers asking to verify results that we sent them, from when
# we were trying to initiate outbound connections.

use strict;
use base qw(DJabberd::Stanza);

sub process {
    my ($self, $conn) = @_;

    warn "Processing dialback verify for $self\n";
    if ($self->result_text =~ /ghetto/) { # FIXME: ghetto, literally
        warn " ... and it's ghetto.  match!\n";
        $conn->dialback_verify_valid(recv_server => $self->recv_server,
                                     orig_server => $self->orig_server,
				     id          => $self->attrs->{"{jabber:server:dialback}id"});
    } else {
        warn " ... no ghetto, invalid.\n";
        $conn->dialback_verify_invalid;
    }
}

# always acceptable
sub acceptable_from_server { 1 }

sub dialback_to {
    my $self = shift;
    return $self->attr("{jabber:server:dialback}to");
}
*recv_server = \&dialback_to;

sub dialback_from {
    my $self = shift;
    return $self->attr("{jabber:server:dialback}from");
}
*orig_server = \&dialback_from;

sub result_text {
    my $self = shift;
    return $self->first_child;
}

1;
