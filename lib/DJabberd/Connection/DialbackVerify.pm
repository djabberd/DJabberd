# outgoing connection to another server for the sole purpose of verifying a dialback result.
package DJabberd::Connection::DialbackVerify;
use strict;
use base 'DJabberd::Connection';
use fields (
            'db_result',    # our DJabberd::Stanza::DialbackResult xml node that started us
            'final_cb',     # our final callback to run ->pass or ->fail on.
            'state',
            'conn',
            );

use IO::Handle;
use Socket qw(PF_INET IPPROTO_TCP SOCK_STREAM);

sub new {
    my ($class, $fromip, $conn, $db_result, $final_cb) = @_;

    my $server = $conn->server;

    my $sock;
    socket $sock, PF_INET, SOCK_STREAM, IPPROTO_TCP;
    unless ($sock && defined fileno($sock)) {
        # WARN: bitch more
        $db_result->verify_failed("socket_create");
        return;
    }

    # TODO: look up SRV record and connect to the right port (not to mention the right IP)
    IO::Handle::blocking($sock, 0);
    connect $sock, Socket::sockaddr_in(5269, Socket::inet_aton($fromip));

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
    warn "$self is writable, reporting for $self->{db_result}\n";

    if ($self->{state} eq "connecting") {
        $self->{state} = "connected";
        $self->start_init_stream(extra_attr => "xmlns:db='jabber:server:dialback'");
        $self->watch_read(1);
    } else {
        return $self->SUPER::event_write;
    }
}

sub on_stream_start {
    my ($self, $ss) = @_;

    my $orig_server = $self->{db_result}->orig_server;
    my $recv_server = $self->{db_result}->recv_server;

    my $id   = $self->{conn}->stream_id;

    my $result = $self->{db_result}->result_text;
    warn "result to verify: $result\n";

    my $res = qq{<db:verify from='$recv_server' to='$orig_server' id='$id'>$result</db:verify>};

    warn "Writing to verify: [$res]\n";

    $self->write($res);
}

sub process_stanza_builtin {
    my ($self, $node) = @_;

    # we only deal with dialback verifies here.  kinda ghetto
    # don't make a Stanza::DialbackVerify, maybe we should.
    unless ($node->element eq "{jabber:server:dialback}verify") {
        return $self->SUPER::process_stanza_builtin($node);
    }

    # <db:verify from='jabber.org' to='207.7.148.210' id='57f34005d7e6f053fb7643bdcec829e425f66d66' type='valid'/>
    # <db:verify from='jabber.org' to='207.7.148.210' id='57f34005d7e6f053fb7643bdcec829e425f66d66' type='invalid'/>

    my $id = $node->attr("{jabber:server:dialback}id");
    my $cb = $self->{final_cb};

    # currently we only do one at a time per connection, so that's why it must match.
    # later we can scatter/gather.
    if ($id ne $self->{conn}->stream_id) {
        $cb->fail("invalid ID");
        $self->close;
        return;
    }

    if ($node->attr("{jabber:server:dialback}type") ne "valid") {
        $cb->fail("invalid");
        $self->close;
        return;
    }

    $cb->pass;
    $self->close;
}

1;
