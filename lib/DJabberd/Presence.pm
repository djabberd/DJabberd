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

sub type {
    my $self = shift;
    return
        $self->attr("{jabber:client}type") ||
        $self->attr("{jabber:server}type");

}

sub to_jid {
    my $self = shift;
    my $to =
        $self->attr("{jabber:client}to") ||
        $self->attr("{jabber:server}to")
        or return undef;
    return DJabberd::JID->new($to) or return undef;
}

sub from_jid {
    my $self = shift;
    my $from =
        $self->attr("{jabber:client}from") ||
        $self->attr("{jabber:server}from")
        or return undef;
    return DJabberd::JID->new($from) or return undef;
}

sub fail {
    my ($self, $conn, $reason) = @_;
    # TODO: figure this out (presence type='error' stuff, when?)
    warn "PRESENCE FAILURE: $reason\n";
    return;
}

sub process {
    confess "No generic 'process' method for $_[0]";
}

sub process_outbound {
    my ($self, $conn) = @_;
    my $type      = $self->type || "available";
    warn "OUTBOUND presence from $conn, type = '$type'\n";

    return $self->fail($conn, "bogus type") unless $type =~ /^\w+$/;

    my $meth = "_process_outbound_$type";
    eval { $self->$meth($conn) };
    if ($@) {
        warn "  ... NOT IMPLEMENTED.\n";
    }
    return;
}

sub process_inbound {
    my ($self, $conn) = @_;
    my $type      = $self->type || "available";
    warn "INBOUND presence from $conn, type = '$type'\n";
    return $self->fail($conn, "bogus type") unless $type =~ /^\w+$/;

    my $to_jid    = $self->to_jid
        or return $self->fail($conn, "no/invalid 'to' attribute");
    my $from_jid  = $self->from_jid
        or return $self->fail($conn, "no/invalid 'from' attribute");

    # find the RosterItem corresponding to this sender, and only once we have
    # it, invoke the next handler
    $conn->run_hook_chain(phase => "RosterLoadItem",
                          args  => [ $to_jid, $from_jid ],
                          methods => {
                              error   => sub {
                                  my ($cb, $reason) = @_;
                                  return $self->fail($conn, "RosterLoadItem hook failed: $reason");
                              },
                              set => sub {
                                  my ($cb, $ritem) = @_;

                                  my $meth = "_process_inbound_$type";
                                  eval { $self->$meth($conn, $ritem) };
                                  if ($@) {
                                      warn "  ... NOT IMPLEMENTED.\n";
                                  }
                              },
                          });
}

sub _process_inbound_available {
    my ($self, $conn, $ritem) = @_;
    $self->deliver($conn);
}

sub _process_inbound_unavailable {
    my ($self, $conn, $ritem) = @_;
    $self->deliver($conn);
}

sub _process_inbound_subscribe {
    my ($self, $conn, $ritem) = @_;

    # ...  vivivy to whatever+pending in in roster
    $self->deliver($conn);  # TEMP
}

sub _process_inbound_subscribed {
    my ($self, $conn, $ritem) = @_;

    # MUST ignore inbound subscribed if we weren't awaiting
    # its arrival
    return unless $ritem && $ritem->subscription->pending_out;

    my $to_jid    = $self->to_jid;

    warn "processing inbound subscribed...\n";
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

sub _process_inbound_probe {
    my ($self, $conn, $ritem) = @_;

    warn("Got a PROBE from " . $ritem->jid->as_string . " and ritem = $ritem\n");
    if ($ritem && $ritem->subscription->sub_from) {
        # ....
    }
}


sub _process_outbound_available {
    my ($self, $conn) = @_;
    if ($conn->is_initial_presence) {
        $conn->send_presence_probes;
    }
    warn "NOT IMPLEMENTED: Outbound presence broadcast!\n";
}

sub _process_outbound_unavailable {
    my ($self, $conn) = @_;
    warn "NOT IMPLEMENTED: Unavailable presence broadcast!\n";
}

sub _process_outbound_subscribe {
    my ($self, $conn) = @_;

    my $contact_jid = $self->to_jid or die "Can't subscribe to bogus jid";

    $conn->run_hook_chain(phase => "RosterSubscribe",
                          args  => [ $contact_jid ],
                          methods => {
                              error   => sub {
                                  my ($cb, $reason) = @_;
                                  return $self->fail($conn, "RosterSubscribe hook failed: $reason");
                              },
                              done => sub {
                                  # XMPPIP-9.2-p2: MUST without exception
                                  # route these, to combat sync issues
                                  # between parties
                                  if ($conn->vhost->handles_jid($contact_jid)) {
                                      my $clone = $self->clone;
                                      $clone->process_inbound($conn);
                                  } else {
                                      warn "Delivering subscribe request...\n";
                                      $self->deliver($conn);
                                  }
                              },
                          },
                          fallback => sub {
                              return $self->fail($conn, "no RosterSubscribe hooks");
                          });
}

sub _process_outbound_subscribed {
    my ($self, $conn) = @_;

    # user wanting to subscribe or approve subscription request to contact
    my $contact_jid = $self->to_jid
        or return $self->fail($conn, "no/invalid 'to' attribute");

    $conn->run_hook_chain(phase => "RosterSubscribed",
                          args  => [ $contact_jid ],
                          methods => {
                              error   => sub {
                                  my ($cb, $reason) = @_;
                                  return $self->fail($conn, "RosterSubscribe hook failed: $reason");
                              },
                              done => sub {

                                  # TODO: based on $type, set things in roster
                                  # now send the packet to the other party
                                  $self->deliver($conn);
                              },
                          },
                          fallback => sub {
                              return $self->fail($conn, "no RosterSubscribe hooks");
                          });
}


1;
