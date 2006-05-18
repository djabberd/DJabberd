package DJabberd::Delivery::Local;
use strict;
use warnings;
use base 'DJabberd::Delivery';

sub run_before { ("DJabberd::Delivery::S2S") }

sub deliver {
    my ($self, $vhost, $cb, $stanza) = @_;
    my $to = $stanza->to_jid                or return $cb->declined;

    my @dconns;
    if ($to->is_bare) {
        @dconns = $vhost->find_conns_of_bare($to)
            or return $cb->declined;
    } else {
        $dconns[0] = $vhost->find_jid($to)
            or return $cb->declined;
    }

    foreach my $c (@dconns) {
        $c->send_stanza($stanza);
    }

    $cb->delivered;
}

1;
