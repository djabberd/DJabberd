package DJabberd::Connection::ClientIn;
use strict;
use base 'DJabberd::Connection';

use fields (
            'requested_roster',  # bool: if user has requested their roster,
            );

sub set_requested_roster {
    my ($self, $val) = @_;
    $self->{requested_roster} = $val;
}

sub requested_roster {
    my $self = shift;
    return $self->{requested_roster};
}

sub on_stream_start {
    my DJabberd::Connection $self = shift;
    my $ss = shift;
    # FIXME: bitch if we're starting a stream when we already have one, and we aren't
    # expeting a new stream to start (like after SSL or SASL)
    $self->start_stream_back($ss,
                             namespace  => 'jabber:client');
}

sub is_server { 0 }

sub on_stanza_received {
    my ($self, $node) = @_;

    my %class = (
                 "{jabber:client}iq"       => 'DJabberd::IQ',
                 "{jabber:client}message"  => 'DJabberd::Message',
                 "{jabber:client}presence" => 'DJabberd::Presence',
                 "{urn:ietf:params:xml:ns:xmpp-tls}starttls"  => 'DJabberd::Stanza::StartTLS',
                 );
    my $class = $class{$node->element} or
        return $self->stream_error("unsupported-stanza-type");

    # same variable as $node, but down(specific)-classed.
    my $stanza = $class->downbless($node, $self);

    $self->run_hook_chain(phase => "filter_incoming_client",
                          args  => [ $stanza ],
                          methods => {
                              reject => sub { },  # just stops the chain
                          },
                          fallback => sub {
                              $self->filter_incoming_client_builtin($stanza);
                          });
}

sub is_authenticated_jid {
    my ($self, $jid) = @_;
    return $jid->eq($self->bound_jid);
}

sub filter_incoming_client_builtin {
    my ($self, $stanza) = @_;

    # <invalid-from/> -- the JID or hostname provided in a 'from'
    # address does not match an authorized JID or validated domain
    # negotiated between servers via SASL or dialback, or between a
    #  client and a server via authentication and resource binding.
    #{=clientin-invalid-from}
    my $from = $stanza->from_jid;

    if ($from && ! $self->is_authenticated_jid($from)) {
        # make sure it is from them, if they care to tell us who they are.
        # (otherwise further processing should assume it's them anyway)
        return $self->stream_error('invalid-from');
    }

    # if no from, we set our own
    if (! $from) {
        my $bj = $self->bound_jid;
        $stanza->set_from($bj->as_string) if $bj;
    }

    $self->run_hook_chain(phase => "switch_incoming_client",
                          args  => [ $stanza ],
                          methods => {
                              process => sub { $stanza->process($self) },
                              deliver => sub { $stanza->deliver($self) },
                          },
                          fallback => sub {
                              $self->switch_incoming_client_builtin($stanza);
                          });
}

sub switch_incoming_client_builtin {
    my ($self, $stanza) = @_;

    if ($stanza->isa("DJabberd::Presence")) {
        $stanza->process_outbound($self);
        return;
    }

    my $to = $stanza->to_jid;
    if (!$to ||
        ($to && $self->vhost->uses_jid($to)))
    {
        $stanza->process($self);
        return;
    }

    $stanza->deliver($self);
}

1;
