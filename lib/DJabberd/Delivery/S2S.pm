package DJabberd::Delivery::S2S;
use strict;
use DJabberd::Queue::ServerOut;
use Scalar::Util;

sub new {
    my ($class) = @_;
    return bless {
        'cache' => {},    # domain -> DJabberd::Queue::ServerOut
        'vhost' => undef, # Vhost we're for, set first on ->register
    }, $class;
}

sub register {
    my ($self, $vhost) = @_;
    $self->{vhost} = $vhost;
    Scalar::Util::weaken($self->{vhost});

    $vhost->register_hook("deliver", sub {
        my ($conn, $cb, $stanza) = @_;
        return $self->s2s_delivery($conn, $cb, $stanza);
    });
}

sub s2s_delivery {
    my ($self, $conn, $cb, $stanza) = @_;

    warn "s2s delivery!\n";
    my $to = $stanza->to_jid                or return $cb->declined;
    warn "  to = $to (" . $to->as_string . ")!\n";

    my $domain = $to->domain;

    # don't initiate outgoing connections back to ourself
    if ($self->{vhost}->name eq $domain) {
        warn "Not doing s2s to ourself\n";
        return $cb->declined;
    }

    # FIXME: let get_conn_for_domain return an error code or something
    # which we can then pass along smarter to the callback, so client gets
    # a good error?
    my $out_queue = $self->get_queue_for_domain($domain) or
        return $cb->declined;

    $out_queue->queue_stanza($stanza, $cb);
}

sub get_queue_for_domain {
    my ($self, $domain) = @_;
    return $self->{cache}{$domain} ||=
        DJabberd::Queue::ServerOut->new(source => $self,
                                        domain => $domain,
                                        vhost  => $self->{vhost});
}

1;
