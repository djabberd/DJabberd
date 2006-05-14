package DJabberd::Stanza::DialbackVerify;
# remote servers asking to verify results that we sent them, from when
# we were trying to initiate outbound connections.

use strict;
use base qw(DJabberd::Stanza);

use DJabberd::Log;
use DJabberd::DialbackParams;

our $logger = DJabberd::Log->get_logger();

sub process {
    my ($self, $conn) = @_;


    $logger->debug("Procesing dialback verify for connection $conn->{id}");

    my $db_params = DJabberd::DialbackParams->new(
                                                  id    => $self->verify_stream_id,
                                                  orig  => $self->dialback_to,
                                                  recv  => $self->dialback_from,
                                                  vhost => $conn->vhost,
                                                  );

    $db_params->verify_callback(
                                result_text => $self->result_text,
                                on_success  => sub {
                                    $logger->debug("Dialback verify success for connection $conn->{id}");
                                    $conn->dialback_verify_valid(recv_server => $self->recv_server,
                                                                 orig_server => $self->orig_server,
                                                                 id          => $self->verify_stream_id);
                                },
                                on_failure => sub {
                                    $logger->warn("Dialback verify success for connection $conn->{id}");
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
