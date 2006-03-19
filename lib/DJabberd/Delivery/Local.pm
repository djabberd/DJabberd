package DJabberd::Delivery::Local;
use strict;
use warnings;
use base 'DJabberd::Delivery';

sub deliver {
    my ($self, $conn, $cb, $stanza) = @_;
    warn "local delivery!\n";
    my $to = $stanza->to_jid                or return $cb->declined;
    warn "  to = $to (" . $to->as_string . ")!\n";

    my $dconn = $conn->vhost->find_jid($to)  or return $cb->declined;
    warn "  dest conn = $dconn\n";

    $dconn->send_stanza($stanza,
                       to   => $to->as_string,
                       from => $stanza->from);
    $cb->delivered;
}

1;
