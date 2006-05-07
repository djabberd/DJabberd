package DJabberd::Delivery::S2S;
use strict;
use warnings;
use base 'DJabberd::Delivery';

use DJabberd::Queue::ServerOut;
use DJabberd::Log;
our $logger = DJabberd::Log->get_logger;

sub run_after { ("DJabberd::Delivery::Local") }

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->{cache} = {}; # domain -> DJabberd::Queue::ServerOut
    return $self;
}

sub deliver {
    my ($self, $conn, $cb, $stanza) = @_;

    my $to = $stanza->to_jid
        or return $cb->declined;

    $logger->debug("s2s delivery attempt for $to");

    # don't initiate outgoing connections back to ourself
    my $vhost  = $self->{vhost};
    my $domain = $to->domain;
    if ($vhost->name eq $domain) {
        $logger->debug("Not doing s2s to ourself");
        return $cb->declined;
    }

    # don't do s2s if the vhost doesn't have it enabled
    unless ($vhost->s2s) {
        $logger->debug("s2s delivery disabled.");
        $cb->declined;
        return;
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
