# outgoing connection to another server for the sole purpose of verifying a dialback result.
package DJabberd::Connection::ServerOut;
use strict;
use base 'DJabberd::Connection';
use fields (
            'state',
            'queue',  # our DJabberd::Queue::ServerOut
            );

use IO::Handle;
use Socket qw(PF_INET IPPROTO_TCP SOCK_STREAM);
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;

    my $ip    = delete $opts{ip};
    my $endpt = delete $opts{endpoint};
    my $queue = delete $opts{queue} or croak "no queue";
    die "unknown options" if %opts;

    croak "No 'ip' or 'endpoint'\n" unless $ip || $endpt;
    $endpt ||= DJabberd::IPEndpoint->new($ip, 5269);

    my $sock;
    socket $sock, PF_INET, SOCK_STREAM, IPPROTO_TCP;
    unless ($sock && defined fileno($sock)) {
        $queue->on_connection_failed("Cannot alloc socket");
        return;
    }
    IO::Handle::blocking($sock, 0);
    my $ip = $endpt->addr;
    connect $sock, Socket::sockaddr_in($endpt->port, Socket::inet_aton($ip));

    my $self = $class->SUPER::new($sock, $queue->vhost->server);
    $self->log->debug("Connecting to '$ip' for '$queue->{domain}'");
    $self->{state}     = "connecting";
    $self->{queue}     = $queue;
    $self->{vhost}     = $queue->vhost;

    Scalar::Util::weaken($self->{queue});

    return $self;
}

sub start_connecting {
    my $self = shift;
    $self->watch_write(1);
}

sub event_write {
    my $self = shift;

    if ($self->{state} eq "connecting") {
        $self->{state} = "connected";

        $self->start_init_stream(extra_attr => "xmlns:db='jabber:server:dialback'",
                                 to         => $self->{queue}->{domain});
        $self->watch_read(1);
    } else {
        return $self->SUPER::event_write;
    }
}

sub on_stream_start {
    my ($self, $ss) = @_;

    warn "We got a stream back from $self!\n";
    unless ($ss->announced_dialback) {
        warn "  .. they don't support dialback.  fail for now.\n";
        $self->{queue}->on_connection_failed($self, "no dialback");
        return;
    }

    warn " ... they support dialback.\n";

    if ($ss->version->supports_features) {
        # they can eat a dick for all we care.  they get no features.
        # what is this weird XMPP 1.0 + old-school Dialback world anyway?
        # maybe we're still confused.  FIXME: care.
        my $features = "<stream:features></stream:features>";
        $self->write($features);
        $self->log->debug("$self->{id} sending '$features'");
    }

    my $vhost       = $self->{queue}->vhost;
    my $orig_server = $vhost->name;
    my $recv_server = $self->{queue}->domain;

    $vhost->generate_dialback_result($ss->id, sub {
        my $res = shift;
        $self->log->debug("$self->{id} sending res '$res'");
        $self->write(qq{<db:result to='$recv_server' from='$orig_server'>$res</db:result>});
    });
}

sub on_stanza_received {
    my ($self, $node) = @_;

    if ($self->xmllog->is_info) {
        $self->log_incoming_data($node);
    }


    # we only deal with dialback verifies here.  kinda ghetto
    # don't make a Stanza::DialbackVerify, maybe we should.
    unless ($node->element eq "{jabber:server:dialback}result") {
        return $self->SUPER::process_stanza_builtin($node);
    }

    unless ($node->attr("{}type") eq "valid") {
        # FIXME: also verify other attributes
        warn "Not valid?\n";
        return;
    }

    warn "connection connected!  from ($self)\n";
    $self->{queue}->on_connection_connected($self);
}

sub event_err {
    my $self = shift;
    $self->{queue}->on_connection_error($self);
    return $self->SUPER::event_err;
}
sub event_hup {
    my $self = shift;
    return $self->event_err;
}

1;
