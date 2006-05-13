package DJabberd::Stanza::DialbackVerify;
# remote servers asking to verify results that we sent them, from when
# we were trying to initiate outbound connections.

use strict;
use base qw(DJabberd::Stanza);

sub process {
    my ($self, $conn) = @_;

    warn "Processing dialback verify for $self\n";
    my $vhost = $conn->vhost;

    $vhost->verify_callback(result_text => $self->result_text,
                            stream_id   => $self->verify_stream_id,
                            on_success  => sub {
                                warn " ... dialback verify valid.\n";
                                $conn->dialback_verify_valid(recv_server => $self->recv_server,
                                                             orig_server => $self->orig_server,
                                                             id          => $self->verify_stream_id);
                            },
                            on_failure => sub {
                                warn " ... dialback verify failure.\n";
                                $conn->dialback_verify_invalid;
                            });
}

# always acceptable
sub acceptable_from_server { 1 }

sub verify_stream_id {
    my $self = shift;
    return $self->attr("{}id");
}

sub dialback_to {
    my $self = shift;
    return $self->attr("{}to");
}
*recv_server = \&dialback_to;

sub dialback_from {
    my $self = shift;
    return $self->attr("{}from");
}
*orig_server = \&dialback_from;

sub result_text {
    my $self = shift;
    return $self->first_child;
}

1;
