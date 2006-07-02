package DJabberd::Message;
use strict;
use base qw(DJabberd::Stanza);

sub on_recv_from_client {
    my ($self, $conn) = @_;

    my $to = $self->to_jid;
    if (! $to) {
        warn "Can't process a message to nobody.\n";
        $conn->close;
        return;
    }

    $DJabberd::Stats::counter{"c2s-Message"}++;
    $self->deliver;
}

sub process {
    my ($self, $conn) = @_;
    die "Can't process a to-server message?";
}

1;
