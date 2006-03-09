package DJabberd::Connection::ServerIn;
use strict;
use base 'DJabberd::Connection';

use DJabberd::Stanza::DialbackResult;

sub start_stream {
    my DJabberd::Connection $self = shift;
    my $ss = shift;

    my $features = "";
    if ($ss->version->supports_features) {
        # unless we're already in SSL mode, advertise it as a feature...
        my $tls = "";
        unless ($self->{ssl}) {
            $tls = "<starttls xmsns='urn:ietf:params:xml:ns:xmpp-tls' />";
        }
        $features = qq{<stream:features>$tls</stream:features>};
    }

    warn "Got an incoming stream.  sending features? " . ($features ? "yes" : "no") . "\n";

    # The receiving entity MUST set the value of the 'version'
    # attribute on the response stream header to either the value
    # supplied by the initiating entity or the highest version number
    # supported by the receiving entity, whichever is lower.
    # {=response-version-is-min}
    my $our_version = $self->server->spec_version;
    my $min_version = $ss->version->min($our_version);
    $self->set_version($min_version);
    my $ver_attr    = $min_version->as_attr_string;

    warn "  version to send back:  $ver_attr\n";

    my $id = $self->stream_id;
    my $sname = $self->server->name;
    my $rv = $self->write(qq{<?xml version="1.0" encoding="UTF-8"?><stream:stream from="$sname" id="$id" $ver_attr xmlns:stream="http://etherx.jabber.org/streams" xmlns="jabber:server" xmlns:db='jabber:server:dialback'>$features});

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
    warn "Dialback verify valid for $self.  from=$opts{recv_server}, to=$opts{orig_server}: $res\n";
    $self->write($res);
}

sub dialback_verify_invalid {
    my ($self, $reason) = @_;
    warn "Dialback verify invalid for $self, reason: $reason\n";
    $self->close_stream;
}


1;
