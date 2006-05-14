package DJabberd::Presence;
use strict;
use base qw(DJabberd::Stanza);
use Carp qw(croak confess);

# TODO:  _process_outbound_invisible   -- seen in wild.  not in spec, but how to handle?
#  Wildfire crew says:
#    Presences of type invisible are not XMPP compliant. That was the
#    old way invisibility was implemented before. The correct way to #
#    implement invisibility is to use JEP-0126: Invisibility that is #
#    based on privacy lists. The server will ignore presences of type
#    # invisible and instead assume that an available presence was
#    sent. In # other words, the server will ignore the invisibility
#    request.

# TODO: inbound_unsubscribe
# TODO: inbound_unsubscribed
# TODO: outbound_unsubscribe
# TODO: outbound_unsubscribed

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
sub make_subscribed {
    my ($class, %opts) = @_;
    my ($from, $to) = map { delete $opts{$_} } qw(from to);
    croak "Invalid options" if %opts;

    my $xml = DJabberd::XMLElement->new("", "presence", { '{}type' => 'subscribed',
                                                          '{}from' => $from->as_string,
                                                          '{}to'   => $to->as_bare_string }, []);
    return $class->downbless($xml);
}

# constructor
sub make_subscribe {
    my ($class, %opts) = @_;
    my ($from, $to) = map { delete $opts{$_} } qw(from to);
    croak "Invalid options" if %opts;

    my $xml = DJabberd::XMLElement->new("", "presence", { '{}type' => 'subscribe',
                                                          '{}from' => $from->as_bare_string,
                                                          '{}to'   => $to->as_bare_string }, []);
    return $class->downbless($xml);
}

# constructor
sub available_stanza {
    my ($class) = @_;
    my $xml = DJabberd::XMLElement->new("", "presence", {}, []);
    return $class->downbless($xml);
}

# constructor
sub unavailable_stanza {
    my ($class) = @_;
    my $xml = DJabberd::XMLElement->new("", "presence", { '{}type' => "unavailable" }, []);
    return $class->downbless($xml);
}

sub type {
    my $self = shift;
    return $self->attr("{}type");
}

sub fail {
    my ($self, $vhost, $reason) = @_;
    # TODO: figure this out (presence type='error' stuff, when?)
    warn "PRESENCE FAILURE: $reason\n";
    return;
}

# like delivery, but handles inbound processing if the target
# is somebody on our domain.  TODO: IQs are going to need
# this same out-vs-in processing.  it should be generic.
sub procdeliver {
    my ($self, $vhost) = @_;

    if ($vhost->isa("DJabberd::Connection")) {
        warn "Deprecated arg of connection to procdeliver at " . join(", ", caller);
        $vhost = $vhost->vhost;
    }

    my $contact_jid = $self->to_jid or die;
    if ($vhost->handles_jid($contact_jid)) {
        my $clone = $self->clone;
        $clone->process_inbound($vhost);
    } else {
        $self->deliver($vhost);
    }
}

sub process {
    confess "No generic 'process' method for $_[0]";
}

sub process_outbound {
    my ($self, $conn) = @_;
    my $type      = $self->type || "available";
    #warn "OUTBOUND presence from $conn, type = '$type'\n";

    my $bjid = $conn->bound_jid;
    return 0 unless $bjid;

    return $self->fail($conn->vhost, "bogus type") unless $type =~ /^\w+$/;

    my $meth = "_process_outbound_$type";
    eval { $self->$meth($conn) };
    if ($@) {
        warn "  ... ERROR: [$@]\n";
    }
    return;
}

sub process_inbound {
    my ($self, $vhost) = @_;
    Carp::confess("Not a vhost") unless $vhost->isa("DJabberd::VHost");

    my $type      = $self->type || "available";

    return $self->fail($vhost, "bogus type") unless $type =~ /^\w+$/;

    my $to_jid    = $self->to_jid
        or return $self->fail($vhost, "no/invalid 'to' attribute");
    my $from_jid  = $self->from_jid
        or return $self->fail($vhost, "no/invalid 'from' attribute");

    # find the RosterItem corresponding to this sender, and only once we have
    # it, invoke the next handler
    $vhost->run_hook_chain(phase => "RosterLoadItem",
                           args  => [ $to_jid, $from_jid ],
                           methods => {
                               error   => sub {
                                   my ($cb, $reason) = @_;
                                   return $self->fail($vhost, "RosterLoadItem hook failed: $reason");
                               },
                               set => sub {
                                   my ($cb, $ritem) = @_;

                                   my $meth = "_process_inbound_$type";
                                   eval { $self->$meth($vhost, $ritem, $from_jid) };
                                   if ($@) {
                                       warn "  ... ERROR: [$@].\n";
                                   }
                               },
                           });
}

sub _process_inbound_available {
    my ($self, $vhost, $ritem) = @_;
    $self->deliver($vhost);
}

sub _process_inbound_unavailable {
    my ($self, $vhost, $ritem) = @_;
    $self->deliver($vhost);
}

sub _process_inbound_subscribe {
    my ($self, $vhost, $ritem, $from_jid) = @_;

    my $to_jid = $self->to_jid;

    # XMPP: server SHOULD auto-reply if contact already subscribed from
    if ($ritem && $ritem->subscription->sub_from) {
        my $subd = DJabberd::Presence->make_subscribed(to   => $from_jid,
                                                       from => $to_jid);
        $subd->procdeliver($vhost);

        # let's act like they probed us too, so we send them our presence.
        my $probe = DJabberd::Presence->probe(from => $from_jid,
                                              to   => $to_jid);
        $probe->procdeliver($vhost);
        return;
    }

    #warn "   ... not already subscribed from, didn't shortcut.\n";

    $ritem ||= DJabberd::RosterItem->new($from_jid);

    # ignore duplicate pending-in subscriptions
    if ($ritem->subscription->pending_in) {
        warn "ignoring dup inbound subscribe, already pending-in.\n";
        return;
    }

    # TODO: HOOK FOR auto-subscribed sending.  violates spec, but LiveJournal
    # could use it.  i think spec isn't thoughtful enough there.

    # mark the roster item as pending-in, and save it:
    $ritem->subscription->set_pending_in;

    $vhost->run_hook_chain(phase => "RosterSetItem",
                           args  => [ $to_jid, $ritem ],
                           methods => {
                               done => sub {
                                   $vhost->roster_push($to_jid, $ritem);
                                   $self->deliver($vhost);
                               },
                               error => sub { my $reason = $_[1]; },
                           },
                           );
}

sub _process_inbound_subscribed {
    my ($self, $vhost, $ritem) = @_;
    Carp::confess("Not a vhost") unless $vhost->isa("DJabberd::VHost");

    # MUST ignore inbound subscribed if we weren't awaiting
    # its arrival
    return unless $ritem && $ritem->subscription->pending_out;

    my $to_jid    = $self->to_jid;

    #warn "processing inbound subscribed...\n";
    $ritem->subscription->got_inbound_subscribed;

    $vhost->run_hook_chain(phase => "RosterSetItem",
                           args  => [ $to_jid, $ritem ],
                           methods => {
                               done => sub {
                                   $vhost->roster_push($to_jid, $ritem);

                                   my $probe = DJabberd::Presence->probe(from => $to_jid,
                                                                         to   => $ritem->jid);
                                   $probe->procdeliver($vhost);
                                   $self->deliver($vhost);
                               },
                               error => sub { my $reason = $_[1]; },
                           },
                           );

}

sub _process_inbound_probe {
    my ($self, $vhost, $ritem, $from_jid) = @_;
    return unless $ritem && $ritem->subscription->sub_from;

    my $jid = $self->to_jid;

    my %map;  # fullstrres -> stanza
    my $add_presence = sub {
        my ($jid, $stanza) = @_;
        $map{$jid->as_string} = $stanza;
    };

    # this hook chain is a little different, it's expected
    # to always fall through to the end.
    $vhost->run_hook_chain(phase => "PresenceCheck",
                           args  => [ $jid, $add_presence ],
                           fallback => sub {
                               # send them
                               foreach my $fullstr (keys %map) {
                                   my $stanza = $map{$fullstr};
                                   my $to_send = $stanza->clone;
                                   $to_send->set_to($from_jid);
                                   $to_send->deliver($vhost);
                               }
                           },
                           );
}

sub broadcast_from {
    my ($self, $conn) = @_;

    my $from_jid = $conn->bound_jid;
    my $vhost    = $conn->vhost;

    my $broadcast = sub {
        my $roster = shift;
        foreach my $it ($roster->from_items) {
            my $dpres = $self->clone;
            $dpres->set_to($it->jid);
            $dpres->set_from($from_jid);
            $dpres->procdeliver($vhost);
        }
    };

    $vhost->run_hook_chain(phase => "RosterGet",
                           args  => [ $from_jid ],
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

    $conn->set_available(1);
    $self->broadcast_from($conn);
}

sub _process_outbound_unavailable {
    my ($self, $conn) = @_;
    if ($self->to_jid) {
        # TODO: directed presence...
        return;
    }

    my $jid = $conn->bound_jid;
    $last_bcast{$jid->as_bare_string}{$jid->as_string} = $self->clone;

    $conn->set_available(0);
    $self->broadcast_from($conn);
}

sub _process_outbound_subscribe {
    my ($self, $conn) = @_;

    my $from_jid    = $conn->bound_jid;
    my $contact_jid = $self->to_jid or die "Can't subscribe to bogus jid";

    # XMPPIP-9.2-p2: MUST without exception
    # route these, to combat sync issues
    # between parties

    my $deliver = sub {
        # let's bare-ifiy our from address, as per the SHOULD in XMPP-IM 8.2.5
        # {=remove-resource-on-presence-out}
        $self->set_from($self->from_jid->as_bare_string);

        $self->procdeliver($conn->vhost);
    };

    my $save = sub {
        my $ritem = shift;
        $conn->vhost->run_hook_chain(phase => "RosterSetItem",
                                     args  => [ $from_jid, $ritem ],
                                     methods => {
                                         done => sub {
                                             $conn->vhost->roster_push($from_jid, $ritem);
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

    $conn->vhost->run_hook_chain(phase => "RosterLoadItem",
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

    $conn->vhost->run_hook_chain(phase => "RosterLoadItem",
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

    $conn->vhost->run_hook_chain(phase => "RosterSetItem",
                                 args  => [ $conn->bound_jid, $ritem ],
                                 methods => {
                                     done => sub {
                                         $conn->vhost->roster_push($conn->bound_jid, $ritem);
                                         $self->procdeliver($conn->vhost);
                                     },
                                     error => sub { my $reason = $_[1]; },
                                 },
                                 );
}


1;
