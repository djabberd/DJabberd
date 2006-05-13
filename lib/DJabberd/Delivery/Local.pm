package DJabberd::Delivery::Local;
use strict;
use warnings;
use base 'DJabberd::Delivery';

sub run_before { ("DJabberd::Delivery::S2S") }

sub deliver {
    my ($self, $vhost, $cb, $stanza) = @_;
    #warn "local delivery!\n";
    my $to = $stanza->to_jid                or return $cb->declined;
    #warn "  to = $to (" . $to->as_string . ")!\n";

    my $dconn = $vhost->find_jid($to)  or return $cb->declined;
    #warn "  dest conn = $dconn\n";

    $dconn->send_stanza($stanza);
    $cb->delivered;
}

1;
