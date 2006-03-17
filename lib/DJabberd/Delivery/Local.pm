package DJabberd::Delivery::Local;
use strict;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub register {
    my ($self, $server) = @_;
    $server->register_hook("deliver", \&local_delivery);
}

sub local_delivery {
    my ($conn, $cb, $stanza) = @_;
    warn "local delivery!\n";
    my $to = $stanza->to_jid                or return $cb->declined;
    warn "  to = $to (" . $to->as_string . ")!\n";

    my $conn = $conn->vhost->find_jid($to)  or return $cb->declined;
    warn "  conn = $conn\n";

    $conn->send_stanza($stanza,
                       to   => $to->as_string,
                       from => $stanza->from);
    $cb->delivered;
}

1;
