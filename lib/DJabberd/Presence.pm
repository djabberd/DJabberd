package DJabberd::Presence;
use strict;
use base qw(DJabberd::Stanza);
use Carp qw(croak confess);

# constructor
sub probe {
    my ($class, %opts) = @_;
    my ($from, $to) = map { delete $opts{$_} } qw(from to);
    croak "Invalid options" if %opts;

    my $xml = DJabberd::XMLElement->new("", "presence", { '{}type' => 'probe',
                                                          '{}from' => $from->as_string,
                                                          '{}to'   => $to->as_bare_string }, []);
    return $class->downbless($xml);
}

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

    if (!$type || $type eq "unavailable") {
        $self->deliver($conn);
        return;
    }

    warn "INBOUND presence from $conn, type = '$type'\n";

    if ($type eq "subscribe" || $type eq "subscribed" || $type eq "probe") {
        # load the rosteritem in question before we decide whether to ignore/act
        $conn->run_hook_chain(phase => "RosterLoadItem",
                              args  => [ $to_jid, $from_jid ],
                              methods => {
                                  error   => sub {
                                      my ($cb, $reason) = @_;
                                      return $fail->("RosterLoadItem hook failed: $reason");
                                  },
                                  set => sub {
                                      my ($cb, $ritem) = @_;

                                      if ($type eq "subscribed") {
                                          if ($ritem && $ritem->subscription->pending_out) {
                                              $self->_process_subscribed($conn, $to_jid, $ritem);
                                          }
                                      } elsif ($type eq "subscribe") {
                                          # ...  vivivy to whatever+pending in in roster

                                          $self->deliver($conn);  # TEMP
                                      } elsif ($type eq "probe") {
                                          warn("Got a PROBE from " . $from_jid->as_string . " and ritem = $ritem\n");
                                          if ($ritem && $ritem->subscription->sub_from) {
                                              # ....
                                          }
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
    my ($self, $conn, $to_jid, $ritem) = @_;

    warn "processing subscribed...\n";
    $ritem->subscription->got_inbound_subscribed;

    $conn->run_hook_chain(phase => "RosterSetItem",
                          args  => [ $to_jid, $ritem ],
                          methods => {
                              done => sub {
                                  # TODO: roster push.
                                  warn "subscribed is processed!\n";
                              },
                              error => sub { my $reason = $_[1]; },
                          },
                          );

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

    warn "OUTBOUND presence from $conn, type = '$type'\n";

    if (! $type || $type eq "unavailable") {
        if ($conn->is_initial_presence) {
            $conn->send_presence_probes;
        }
        warn "NOT IMPLEMENTED: Outbound presence broadcast!\n";
        return;
    }

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
                                      # XMPPIP-9.2-p2: MUST without exception
                                      # route these, to combat sync issues
                                      # between parties
                                      if ($conn->vhost->handles_jid($contact_jid)) {
                                          my $clone = $self->clone;
                                          $clone->process_inbound($conn);
                                      } else {
                                          $self->deliver($conn);
                                      }
                                  },
                              },
                              fallback => sub {
                                  return $fail->("no RosterSubscribe hooks");
                              });

        return;
    }

    # user wanting to subscribe or approve subscription request to contact
    if ($type eq "subscribed") {
        my $contact_jid = DJabberd::JID->new($to)
            or return $fail->("no/invalid 'to' attribute");

        $conn->run_hook_chain(phase => "RosterSubscribed",
                              args  => [ $contact_jid ],
                              methods => {
                                  error   => sub {
                                      my ($cb, $reason) = @_;
                                      return $fail->("RosterSubscribe hook failed: $reason");
                                  },
                                  done => sub {

                                      # TODO: based on $type, set things in roster
                                      # now send the packet to the other party
                                      $self->deliver($conn);
                                  },
                              },
                              fallback => sub {
                                  return $fail->("no RosterSubscribe hooks");
                              });

        return;
    }

    warn "$self PRESENCE OUTBOUND type='$type' from $conn not implemented\n";
}


1;
