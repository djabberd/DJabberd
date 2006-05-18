package DJabberd::Connection::ClientIn;
use strict;
use base 'DJabberd::Connection';

use fields (
            # {=server-needs-client-wanted-roster-state}
            'requested_roster',      # bool: if user has requested their roster,

            'got_initial_presence',  # bool: if user has already sent their initial presence
            'is_available',          # bool: is an "available resource"
            );

sub requested_roster {
    my $self = shift;
    return $self->{requested_roster};
}

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
            $probe->procdeliver($self->vhost);
        }
    };

    $self->vhost->run_hook_chain(phase => "RosterGet",
                                 args  => [ $self->bound_jid ],
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

sub on_stream_start {
    my DJabberd::Connection $self = shift;
    my $ss = shift;
    my $to_host = $ss->to;
    my $vhost = $self->server->lookup_vhost($to_host);
    unless ($vhost) {
        # FIXME: send proper "vhost not found message"
        # spec says:
        #   -- we have to start stream back to them,
        #   -- then send stream error
        #   -- stream should have proper 'from' address (but what if we have 2+)
        # If the error occurs while the stream is being set up, the receiving entity MUST still send the opening <stream> tag, include the <error/> element as a child of the stream element, send the closing </stream> tag, and terminate the underlying TCP connection. In this case, if the initiating entity provides an unknown host in the 'to' attribute (or provides no 'to' attribute at all), the server SHOULD provide the server's authoritative hostname in the 'from' attribute of the stream header sent before termination
        $self->log->info("No vhost found for host '$to_host', disconnecting");
        $self->close;
        return;
    }
    $self->set_vhost($vhost);

    # FIXME: bitch if we're starting a stream when we already have one, and we aren't
    # expecting a new stream to start (like after SSL or SASL)
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

    $self->vhost->run_hook_chain(phase => "filter_incoming_client",
                                 args  => [ $stanza, $self ],
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
    my $vhost = $self->vhost;

    if ($from && ! $self->is_authenticated_jid($from)) {
        # make sure it is from them, if they care to tell us who they are.
        # (otherwise further processing should assume it's them anyway)

        # libgaim quirks bug.  libgaim sends bogus from on IQ errors.
        # see doc/quirksmode.txt.
        if ($vhost->quirksmode && $stanza->isa("DJabberd::IQ") &&
            $stanza->type eq "error" && $stanza->from eq $stanza->to) {
            # fix up from address
            $from = $self->bound_jid;
            $stanza->set_from($from);
        } else {
            return $self->stream_error('invalid-from');
        }
    }

    # if no from, we set our own
    if (! $from) {
        my $bj = $self->bound_jid;
        $stanza->set_from($bj->as_string) if $bj;
    }

    $vhost->run_hook_chain(phase => "switch_incoming_client",
                           args  => [ $stanza ],
                           methods => {
                               process => sub { $stanza->process($self) },
                               deliver => sub { $stanza->deliver($self) },
                           },
                           fallback => sub {
                               $stanza->on_recv_from_client($self);
                           });
}

1;
