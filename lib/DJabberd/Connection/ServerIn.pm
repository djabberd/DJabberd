package DJabberd::Connection::ServerIn;
use strict;
use base 'DJabberd::Connection';

use DJabberd::Stanza::DialbackResult;

sub start_stream {
    my DJabberd::Connection $self = shift;

    # unless we're already in SSL mode, advertise it as a feature...
    my $tls = "";
    unless ($self->{ssl}) {
        $tls = "<starttls xmsns='urn:ietf:params:xml:ns:xmpp-tls' />";
    }

    my $id = $self->stream_id;
    my $sname = $self->server->name;
    my $rv = $self->write(qq{<?xml version="1.0" encoding="UTF-8"?>
                                 <stream:stream from="$sname" id="$id" version="1.0" xmlns:stream="http://etherx.jabber.org/streams" xmlns="jabber:server" xmlns:db='jabber:server:dialback'>
                                 <stream:features>
$tls
</stream:features>});

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



1;
