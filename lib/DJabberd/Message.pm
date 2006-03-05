package DJabberd::Message;
use strict;
use base qw(DJabberd::Stanza);

sub process {
    my ($self, $conn) = @_;

    my $to = $self->to;
    my $dconn = DJabberd::Connection->find_connection($to);
    warn "CONN of jid '$to' = $conn\n";
    if ($dconn) {
        $dconn->send_message($conn, $self);
    } else {
        my $self_jid = $conn->jid;
        # FIXME: keep message body better
        $conn->write("<message from='$to' to='$self_jid' type='error'><x xmlns='jabber:x:event'><composing/></x><body>lost</body><html xmlns='http://jabber.org/protocol/xhtml-im'><body xmlns='http://www.w3.org/1999/xhtml'>lost</body></html><error code='404'>Not Found</error></message>");
    }
}

sub to {
    return $_[0]->attr("{jabber:client}to");
}

sub from {
    return $_[0]->attr("{jabber:client}from");
}

1;
