# outgoing connection to another server for the sole purpose of verifying a dialback result.
package DJabberd::Connection::DialbackVerify;
use strict;
use base 'DJabberd::Connection';

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

use fields (
            'db_result',    # our DJabberd::Stanza::DialbackResult xml node that started us
            'final_cb',     # our final callback to run ->pass or ->fail on.
            'state',
            'conn',
            );

use IO::Handle;
use Socket qw(PF_INET PF_INET6 IPPROTO_TCP SOCK_STREAM AF_INET AF_INET6);
use Socket6;

sub new {
    my ($class, $endpt, $conn, $db_result, $final_cb) = @_;

    my $server = $conn->server;

    my $sock;
    if($endpt->ver == 6) {
        socket $sock, PF_INET6, SOCK_STREAM, IPPROTO_TCP;
    } else {
        socket $sock, PF_INET, SOCK_STREAM, IPPROTO_TCP;
    }
    unless ($sock && defined fileno($sock)) {
        # WARN: bitch more
        $db_result->verify_failed("socket_create");
        return;
    }

    # TODO: look up SRV record and connect to the right port (not to mention the right IP)

    my $fromip = $endpt->addr;
    my $port   = $endpt->port;

    $logger->debug("Attempting to connect to '$fromip'");
    IO::Handle::blocking($sock, 0);
    if($endpt->ver == 6) {
        connect $sock, Socket::sockaddr_in6($port, Socket::inet_pton(AF_INET6, $fromip));
    } else {
        connect $sock, Socket::sockaddr_in($port, Socket::inet_aton($fromip));
    }
    $DJabberd::Stats::counter{connect}++;

    my $self = $class->SUPER::new($sock, $server);
    $self->{db_result} = $db_result;

    $self->{final_cb}  = $final_cb;
    $self->{state}     = "connecting";

    $self->{conn}      = $conn;
    Scalar::Util::weaken($self->{conn});

    $self->watch_write(1);
}

sub event_write {
    my $self = shift;

    if ($self->{state} eq "connecting") {
        $self->{state} = "connected";
        $self->log->debug("$self->{id} connected for DialbackResult " . $self->{db_result}->orig_server);
        $self->start_init_stream(extra_attr => "xmlns:db='jabber:server:dialback'",
                                 to         => $self->{db_result}->orig_server);
        $self->watch_read(1);
    } else {
        return $self->SUPER::event_write;
    }
}

sub namespace { 'jabber:server' }

sub on_stream_start {
    my ($self, $ss) = @_;

    $self->{in_stream} = 1;
    my $orig_server = $self->{db_result}->orig_server;
    my $recv_server = $self->{db_result}->recv_server;

    my $id   = $self->{conn}->stream_id;

    my $result = $self->{db_result}->result_text;
    $logger->debug("result to verify: $result");

    my $res = qq{<db:verify from='$recv_server' to='$orig_server' id='$id'>$result</db:verify>};

    $logger->debug("Writing to verify: [$res]");

    $self->write($res);
}

sub on_stanza_received {
    my ($self, $node) = @_;

    if ($self->xmllog->is_info) {
        $self->log_incoming_data($node);
    }

    # we only deal with dialback verifies here.  kinda ghetto
    # don't make a Stanza::DialbackVerify, maybe we should.
    unless ($node->element eq "{jabber:server:dialback}verify") {
        return $self->SUPER::process_incoming_stanza_from_s2s_out($node);
    }

    my $id = $node->attr("{}id");
    my $cb = $self->{final_cb};

    # currently we only do one at a time per connection, so that's why it must match.
    # later we can scatter/gather.
    if ($id ne $self->{conn}->stream_id) {
        $cb->fail("invalid ID '$id' ne '" . $self->{conn}->stream_id . "'");
        $self->close;
        return;
    }

    if ($node->attr("{}type") ne "valid") {
        $cb->fail("invalid");
        $self->close;
        return;
    }

    $cb->pass;
    $self->close;
}

1;
