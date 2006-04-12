package DJabberd::Presence;
use strict;
use base qw(DJabberd::Stanza);
use Carp qw(croak confess);

# used by DJabberd::PresenceChecker::Local.
my %last_bcast;   # barejidstring -> { full_jid_string -> $cloned_pres_stanza }

sub local_presence_info {
    my ($class, $jid) = @_;
    my $barestr = $jid->as_bare_string;
    return $last_bcast{$barestr} || {};
}

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

# constructor
sub available_stanza {
    my ($class) = @_;
    my $xml = DJabberd::XMLElement->new("", "presence", {}, []);
    return $class->downbless($xml);
}

sub type {
    my $self = shift;
    return
        $self->attr("{jabber:client}type") ||
        $self->attr("{jabber:server}type") ||
        $self->attr("{}type");
}

sub fail {
    my ($self, $conn, $reason) = @_;
    # TODO: figure this out (presence type='error' stuff, when?)
    warn "PRESENCE FAILURE: $reason\n";
    return;
}

# like delivery, but handles inbound processing if the target
# is somebody on our domain.  TODO: IQs are going to need
# this same out-vs-in processing.  it should be generic.
sub procdeliver {
    my ($self, $conn) = @_;
    my $contact_jid = $self->to_jid or die;
    if ($conn->vhost->handles_jid($contact_jid)) {
        my $clone = $self->clone;
        $clone->process_inbound($conn);
    } else {
        $self->deliver($conn);
    }
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
        warn "  ... ERROR: [$@]\n";
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
                                  eval { $self->$meth($conn, $ritem, $from_jid) };
                                  if ($@) {
                                      warn "  ... ERROR: [$@].\n";
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
    my ($self, $conn, $ritem, $from_jid) = @_;

    my $subs = $ritem ? $ritem->subscription : "";
    warn "inbound subscribe!  from=$from_jid, curr_subs=$subs\n";

    # XMPP: server SHOULD auto-reply if contact already subscribed from
    if ($ritem && $ritem->subscription->sub_from) {
        # TODO: auto-reply with 'subscribed'
        return;
    }

    warn "   ... not already subscribed from, didn't shortcut.\n";

    $ritem ||= DJabberd::RosterItem->new($from_jid);
    my $to_jid = $self->to_jid;

    # ignore duplicate pending-in subscriptions
    if ($ritem->subscription->pending_in) {
        warn "ignoring dup inbound subscribe, already pending-in.\n";
        return;
    }

    # TODO: HOOK FOR auto-subscribed sending.  violates spec, but LiveJournal
    # could use it.  i think spec isn't thoughtful enough there.

    # mark the roster item as pending-in, and save it:
    $ritem->subscription->set_pending_in;
    warn "   ... now subscription is: $subs\n";

    $conn->run_hook_chain(phase => "RosterSetItem",
                          args  => [ $to_jid, $ritem ],
                          methods => {
                              done => sub {
                                  # no roster push, i don't think.  (TODO: re-read spec)
                                  warn "subscribe is saved.\n";
                                  $self->deliver($conn);
                              },
                              error => sub { my $reason = $_[1]; },
                          },
                          );
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
    my ($self, $conn, $ritem, $from_jid) = @_;
    my $subs = $ritem->subscription;
    warn("Got a PROBE regarding " . $ritem->jid->as_string . " and whose subscription is $subs\n");
    # ignore if they don't have access
    return unless $ritem && $ritem->subscription->sub_from;

    my $jid = $self->to_jid;
    warn " probe is checking on jid=$jid\n";

    my %map;  # fullstrres -> stanza
    my $add_presence = sub {
        my ($jid, $stanza) = @_;
        warn "  ... adding presence $jid = $stanza\n";
        $map{$jid->as_string} = $stanza;
    };

    # this hook chain is a little different, it's expected
    # to always fall through to the end.
    $conn->run_hook_chain(phase => "PresenceCheck",
                          args  => [ $jid, $add_presence ],
                          fallback => sub {
                              # send them
                              warn "  ... fallback!\n";
                              foreach my $fullstr (keys %map) {
                                  my $stanza = $map{$fullstr};
                                  my $to_send = $stanza->clone;
                                  $to_send->set_to($from_jid);
                                  $to_send->deliver($conn);
                              }
                          },
                          );
}

sub _process_broadcast_outbound {
    my ($self, $conn) = @_;
    my $from_jid = $conn->bound_jid;

    my $broadcast = sub {
        my $roster = shift;
        foreach my $it ($roster->to_items) {
            warn "Broadcasting presence to @{[ $it->jid ]} ...\n";
            my $dpres = $self->clone;
            $dpres->set_to($it->jid);
            $dpres->procdeliver($conn);
        }
    };

    $conn->run_hook_chain(phase => "RosterGet",
                          methods => {
                              set_roster => sub {
                                  my (undef, $roster) = @_;
                                  $broadcast->($roster);
                              },
                          });
}

sub _process_outbound_available {
    my ($self, $conn) = @_;
    if ($self->to_jid) {
        # TODO: directed presence...
        return;
    }

    my $jid = $conn->bound_jid;
    $last_bcast{$jid->as_bare_string}{$jid->as_string} = $self->clone;

    if ($conn->is_initial_presence) {
        $conn->send_presence_probes;
    }

    $self->_process_broadcast_outbound($conn);
}

sub _process_outbound_unavailable {
    my ($self, $conn) = @_;
    if ($self->to_jid) {
        # TODO: directed presence...
        return;
    }

    my $jid = $conn->bound_jid;
    $last_bcast{$jid->as_bare_string}{$jid->as_string} = $self->clone;

    $self->_process_broadcast_outbound($conn);
}

sub _process_outbound_subscribe {
    my ($self, $conn) = @_;

    my $from_jid    = $conn->bound_jid;
    my $contact_jid = $self->to_jid or die "Can't subscribe to bogus jid";

    # XMPPIP-9.2-p2: MUST without exception
    # route these, to combat sync issues
    # between parties

    my $deliver = sub {
        $self->procdeliver($conn);
    };

    my $save = sub {
        my $ritem = shift;
        $conn->run_hook_chain(phase => "RosterSetItem",
                              args  => [ $from_jid, $ritem ],
                              methods => {
                                  done => sub {
                                      # TODO: roster push, then:
                                      $deliver->();
                                  },
                                  error => sub { my $reason = $_[1]; },
                              },
                              );
    };

    my $on_load = sub {
        my (undef, $ritem) = @_;

        # not in roster, skip.
        $ritem ||= DJabberd::RosterItem->new($contact_jid);

        if ($ritem->subscription->got_outbound_subscribe) {
            # subscription modified, must save, which will then
            # deliver when done.
            $save->($ritem);
        } else {
            $deliver->();
        }
    };

    $conn->run_hook_chain(phase => "RosterLoadItem",
                          args  => [ $from_jid, $contact_jid ],
                          methods => {
                              error   => sub {
                                  my (undef, $reason) = @_;
                                  return $self->fail($conn, "RosterLoadItem hook failed: $reason");
                              },
                              set => $on_load,
                          });
}


sub _process_outbound_subscribed {
    my ($self, $conn) = @_;

    # user wanting to subscribe or approve subscription request to contact
    my $contact_jid = $self->to_jid
        or return $self->fail($conn, "no/invalid 'to' attribute");

    $conn->run_hook_chain(phase => "RosterLoadItem",
                          args  => [ $conn->bound_jid, $contact_jid ],
                          methods => {
                              error   => sub {
                                  my (undef, $reason) = @_;
                                  return $self->fail($conn, "RosterLoadItem hook failed: $reason");
                              },
                              set => sub {
                                  my (undef, $ritem) = @_;

                                  # not in roster, skip.
                                  return unless $ritem;

                                  my $subs = $ritem->subscription;
                                  warn "   current subscription = $subs\n";

                                  # skip unless we were in pending in state
                                  return unless $subs->pending_in;

                                  $self->_process_outbound_subscribed_with_ritem($conn, $ritem);
                              },
                          });
}

# second stage of outbound 'subscribed' processing, once we load the item and
# decide to skip processing or not.  see above.
sub _process_outbound_subscribed_with_ritem {
    my ($self, $conn, $ritem) = @_;

    $ritem->subscription->got_outbound_subscribed;

    my $subs = $ritem->subscription;
    warn "   updated subscription = $subs\n";

    $conn->run_hook_chain(phase => "RosterSetItem",
                          args  => [ $conn->bound_jid, $ritem ],
                          methods => {
                              done => sub {
                                  # TODO: roster push
                                  warn "outbound subscribed is saved.\n";
                                  $self->procdeliver($conn);
                              },
                              error => sub { my $reason = $_[1]; },
                          },
                          );
}


1;
