package DJabberd::Presence;
use strict;
use base qw(DJabberd::Stanza);
use Carp qw(confess);

sub process {
    confess "No generic 'process' method for $_[0]";
}

sub process_inbound {
    my ($self, $conn) = @_;

    my $fail = sub {
        my $reason = shift;
        warn "PRESENCE INBOUND FAILURE: $reason\n";
        return;
    };

    my $is_client = $conn->isa("DJabberd::Connection::ClientIn");
    my $ns        = $is_client ? "{jabber:client}" : "{jabber:server}";
    my $type      = $self->attr("${ns}type");
    my $to        = $self->attr("${ns}to");
    my $to_jid    = DJabberd::JID->new($to)
        or return $fail->("no/invalid 'to' attribute");
    my $from      = $self->attr("${ns}from");
    my $from_jid  = DJabberd::JID->new($from)
        or return $fail->("no/invalid 'from' attribute");

    if ($type eq "subscribed") {
        # somebody said we're subscribed to them now, but we want
        # to ignore it unless user was waiting on said announcement
        $conn->run_hook_chain(phase => "RosterLoadItem",
                              args  => [ $to_jid, $from_jid ],
                              methods => {
                                  error   => sub {
                                      my ($cb, $reason) = @_;
                                      return $fail->("RosterLoadItem hook failed: $reason");
                                  },
                                  set => sub {
                                      my ($cb, $ritem) = @_;
                                      if ($ritem && $ritem->subscription->pending_out) {
                                          $self->_process_subscribed($conn->vhost, $ritem, $from_jid, $to_jid);
                                      }
                                  },
                              },
                              fallback => sub {
                                  return $fail->("no RosterLoadItem hooks");
                              });
        return;
    }

    warn "$self PRESENCE INBOUND type='$type' from $conn not implemented\n";
}

# called after filtering.  at this point, we know $to_jid was waiting
# for the 'subscribed' stanza
sub _process_subscribed {
    my ($self, $vhost, $ritem, $from_jid, $to_jid) = @_;


}

sub process_outbound {
    my ($self, $conn) = @_;

    my $ns        = "{jabber:client}";
    my $type      = $self->attr("${ns}type");
    my $to        = $self->attr("${ns}to");

    my $fail = sub {
        my $reason = shift;
        warn "PRESENCE FAILURE: $reason\n";
        return;
    };

    # user wanting to subscribe to target
    if ($type eq "subscribe") {
        my $contact_jid = DJabberd::JID->new($to)
            or return $fail->("no/invalid 'to' attribute");

        $conn->run_hook_chain(phase => "RosterSubscribe",
                              args  => [ $contact_jid ],
                              methods => {
                                  error   => sub {
                                      my ($cb, $reason) = @_;
                                      return $fail->("RosterSubscribe hook failed: $reason");
                                  },
                                  done => sub {
                                      # now send the packet to the other party
                                      $self->deliver($conn);
                                  },
                              },
                              fallback => sub {
                                  return $fail->("no RosterSubscriber hooks");
                              });

        return;
    }

    warn "$self PRESENCE OUTBOUND type='$type' from $conn not implemented\n";
}


1;
