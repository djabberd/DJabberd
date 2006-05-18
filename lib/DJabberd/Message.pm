package DJabberd::Message;
use strict;
use base qw(DJabberd::Stanza);

sub on_recv_from_client {
    my ($self, $conn) = @_;

    my $to = $self->to_jid;
    if (! $to || $conn->vhost->uses_jid($to)) {
        # FIXME: use proper stream error code.
        warn "Can't process a message to the server.\n";
        $conn->close;
        return;
    }

    $self->deliver;
}

sub process {
    my ($self, $conn) = @_;
    die "Can't process a to-server message?";
}

1;
