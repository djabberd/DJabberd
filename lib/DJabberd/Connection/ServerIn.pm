package DJabberd::Connection::ServerIn;
use strict;
use base 'DJabberd::Connection';

use DJabberd::Stanza::DialbackResult;

sub start_stream {
    my DJabberd::Connection $self = shift;
    my $sax_data = shift;

    # unless we're already in SSL mode, advertise it as a feature...
    my $tls = "";
    unless ($self->{ssl}) {
        $tls = "<starttls xmsns='urn:ietf:params:xml:ns:xmpp-tls' />";
    }

    my $features = "";
    my $dialback_attr = $sax_data->{Attributes}{"{http://www.w3.org/2000/xmlns/}db"};
    unless ($dialback_attr && $dialback_attr->{Value} eq "jabber:server:dialback") {
        $features = qq{<stream:features>$tls</stream:features>};
    }

    warn "Got an incoming stream.  sending features? " . ($features ? "yes" : "no") . "\n";

    my $id = $self->stream_id;
    my $sname = $self->server->name;
    my $rv = $self->write(qq{<?xml version="1.0" encoding="UTF-8"?><stream:stream from="$sname" id="$id" version="1.0" xmlns:stream="http://etherx.jabber.org/streams" xmlns="jabber:server" xmlns:db='jabber:server:dialback'>$features});

    return;
}

sub process_stanza_builtin {
    my ($self, $node) = @_;

    my %stanzas = (
                   "{jabber:server:dialback}result" => "DJabberd::Stanza::DialbackResult",
                   );

    my $class = $stanzas{$node->element};
    unless ($class) {
        return $self->SUPER::process_stanza_builtin($node);
    }

    my $obj = $class->new($node);
    $obj->process($self);
}

sub dialback_verify_valid {
    my $self = shift;
    my %opts = @_;

    my $res = qq{<db:result from='$opts{recv_server}' to='$opts{orig_server}' type='valid'/>};
    warn "Dialback verify valid for $self.  from=$opts{from}, to=$opts{to}: $res\n";
    $self->write($res);
}

sub dialback_verify_invalid {
    my ($self, $reason) = @_;
    warn "Dialback verify invalid for $self, reason: $reason\n";
    # TODO: do something better:
    #  If the connection is invalid, then the Receiving Server MUST terminate both the XML stream and the underlying TCP connection.
    # $self->terminate_stream;
    $self->close;
}


1;
