package DJabberd::Connection::ClientIn;
use strict;
use base 'DJabberd::Connection';

use fields (
            # {=server-needs-client-wanted-roster-state}
            'requested_roster',      # bool: if user has requested their roster,

            'got_initial_presence',  # bool: if user has already sent their initial presence
            'is_available',          # bool: is an "available resource"
            );

sub set_requested_roster {
    my ($self, $val) = @_;
    $self->{requested_roster} = $val;
}

sub set_available {
    my ($self, $val) = @_;
    $self->{is_available} = $val;
}

sub is_available {
    my $self = shift;
    return $self->{is_available};
}

# called when a presence broadcast is received.  on first time,
# returns tru.
sub is_initial_presence {
    my $self = shift;
    return 0 if $self->{got_initial_presence};
    return $self->{got_initial_presence} = 1;
}

sub send_presence_probes {
    my $self = shift;

    my $send_probes = sub {
        my $roster = shift;
        # go through rosteritems that are subscribed to our
        # presence.  (XMPPIM-5.1.2-p2)
        my $from_jid = $self->bound_jid;
        foreach my $it ($roster->to_items) {
            my $probe = DJabberd::Presence->probe(to => $it->jid, from => $from_jid);
            #warn "Sending probe: " . $probe->as_xml . "\n";
            $probe->procdeliver($self);  # FIXME: lame that we need to pass $self to this, just for the hook chain running
        }
    };

    $self->run_hook_chain(phase => "RosterGet",
                          methods => {
                              set_roster => sub {
                                  my (undef, $roster) = @_;
                                  $send_probes->($roster);
                              },
                          });
}

sub close {
    my $self = shift;

    # send an unavailable presence broadcast if we've gone away
    if ($self->is_available) {
        my $unavail = DJabberd::Presence->unavailable_stanza;
        $unavail->broadcast_from($self);
    }

    $self->SUPER::close;
}

sub namespace {
    return "jabber:client";
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

    if ($self->xmllog->is_info) {
        $self->log_incoming_data($node);
    }

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
