package DJabberd::Connection::ClientIn;
use strict;
use base 'DJabberd::Connection';

use fields (
            # {=server-needs-client-wanted-roster-state}
            'requested_roster',      # bool: if user has requested their roster,

            'got_initial_presence',  # bool: if user has already sent their initial presence
            'is_available',          # bool: is an "available resource"
            'directed_presence',     # the jids we have sent directed presence too
            );

sub directed_presence {
    my $self = shift;
    return keys %{$self->{directed_presence}};
}

sub add_directed_presence {
    my ($self, $to_jid) = @_;
    $self->{directed_presence}->{$to_jid}++;
}

sub clear_directed_presence {
    my $self = shift;
    $self->{directed_presence} = {};
}

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
        # go through rosteritems who we're subscribed to
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
        # set unavailable here, BEFORE we sent out unavailable stanzas,
        # so if the stanzas 'bounce' or otherwise write back to our full JID,
        # they'll either drop/bounce instead of writing to what will
        # soon be a dead full JID.
        $self->set_available(0);

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
    return $self->close_no_vhost($to_host)
        unless ($vhost);

    $self->set_vhost($vhost);

    # FIXME: bitch if we're starting a stream when we already have one, and we aren't
    # expecting a new stream to start (like after SSL or SASL)
    $self->start_stream_back($ss,
                             namespace  => 'jabber:client');
}

sub is_server { 0 }

my %element2class = (
             "{jabber:client}iq"       => 'DJabberd::IQ',
             "{jabber:client}message"  => 'DJabberd::Message',
             "{jabber:client}presence" => 'DJabberd::Presence',
             "{urn:ietf:params:xml:ns:xmpp-tls}starttls"  => 'DJabberd::Stanza::StartTLS',
             );

sub on_stanza_received {
    my ($self, $node) = @_;

    if ($self->xmllog->is_info) {
        $self->log_incoming_data($node);
    }

    my $class = $element2class{$node->element} or
        return $self->stream_error("unsupported-stanza-type");

    # same variable as $node, but down(specific)-classed.
    my $stanza = $class->downbless($node, $self);

    $self->vhost->hook_chain_fast("filter_incoming_client",
                                  [ $stanza, $self ],
                                  {
                                      reject => sub { },  # just stops the chain
                                  },
                                  \&filter_incoming_client_builtin,
                                  );
}

sub is_authenticated_jid {
    my ($self, $jid) = @_;
    return $jid->eq($self->bound_jid);
}


# This is not really a method, but gets invoked as a hookchain item
# so if you subclass this class, this will still get called

sub filter_incoming_client_builtin {
    my ($vhost, $cb, $stanza, $self) = @_;

    # <invalid-from/> -- the JID or hostname provided in a 'from'
    # address does not match an authorized JID or validated domain
    # negotiated between servers via SASL or dialback, or between a
    #  client and a server via authentication and resource binding.
    #{=clientin-invalid-from}
    my $from = $stanza->from_jid;

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

    $vhost->hook_chain_fast("switch_incoming_client",
                            [ $stanza ],
                            {
                                process => sub { $stanza->process($self) },
                                deliver => sub { $stanza->deliver($self) },
                            },
                            sub {
                                $stanza->on_recv_from_client($self);
                            });

}

1;
