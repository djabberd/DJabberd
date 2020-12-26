package DJabberd::Delivery::S2S;
use strict;
use warnings;
use base 'DJabberd::Delivery';

use DJabberd::Queue::ServerOut;
use DJabberd::Log;
our $logger = DJabberd::Log->get_logger;

sub run_after { ("DJabberd::Delivery::Local") }

sub deliver {
    my ($self, $vhost, $cb, $stanza) = @_;
    die unless $vhost == $self->{vhost}; # sanity check

    # don't do s2s if the vhost doesn't have it enabled
    unless ($vhost->s2s) {
        $cb->declined;
        return;
    }

    my $to = $stanza->to_jid
        or return $cb->declined;

    # don't initiate outgoing connections back to ourself
    my $domain = $to->domain;
    if ($vhost->handles_domain($domain)) {
        return $cb->declined;
    }

    $logger->debug("s2s delivery attempt for $to");

    # FIXME: let get_conn_for_domain return an error code or something
    # which we can then pass along smarter to the callback, so client gets
    # a good error?
    my $out_queue = $self->get_queue_for_domain($domain) or
        return $cb->declined;

    $DJabberd::Stats::counter{deliver_s2s}++;
    $out_queue->queue_stanza($stanza, $cb);
}

sub get_queue_for_domain {
    my ($self, $domain) = @_;
    # TODO: we need to clean this periodically, like when connections timeout or fail
    my $queue = $self->{vhost}->find_queue($domain);
    unless($queue) {
	$queue = DJabberd::Queue::ServerOut->new(source => $self,
                                        domain => $domain,
                                        vhost  => $self->{vhost});
	$self->{vhost}->add_queue($domain,$queue);
    }
    return $queue;
}

1;
