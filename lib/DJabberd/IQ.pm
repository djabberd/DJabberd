package DJabberd::IQ;
use strict;
use base qw(DJabberd::Stanza);

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

# DO NOT OVERRIDE THIS
sub process {
    my DJabberd::IQ $self = shift;
    my $conn = shift;

    # FIXME: handle 'result'/'error' IQs from when we send IQs
    # out, like in roster pushes

    my $handler = {
        'get-{jabber:iq:roster}query' => \&process_iq_getroster,
        'set-{jabber:iq:roster}query' => \&process_iq_setroster,
        'get-{jabber:iq:auth}query' => \&process_iq_getauth,
        'set-{jabber:iq:auth}query' => \&process_iq_setauth,
    };

    $conn->run_hook_chain(phase    => "c2s-iq",
                          args     => [ $self ],
                          fallback => sub {
                              my $sig = $self->signature;
                              my $meth = $handler->{$sig};
                              unless ($meth) {
                                  $self->send_error;
                                  $logger->warn("Unknown IQ packet: $sig");
                                  return;
                              }
                              $meth->($conn, $self);
                          });
}

sub signature {
    my $iq = shift;
    my $fc = $iq->first_element;
    # FIXME: should signature ever get called on a bogus IQ packet?
    return $iq->type . "-" . ($fc ? $fc->element : "(BOGUS)");
}

sub send_result {
    my DJabberd::IQ $self = shift;
    $self->send_reply("result");
}

sub send_error {
    my DJabberd::IQ $self = shift;
    # TODO: take more parameters
    $self->send_reply("error");
}

# caller must send well-formed XML (but we do the wrapping element)
sub send_result_raw {
    my DJabberd::IQ $self = shift;
    my $raw = shift;
    return $self->send_reply("result", $raw);
}

sub send_reply {
    my DJabberd::IQ $self = shift;
    my ($type, $raw) = @_;

    my $conn = $self->{connection}
        or return;

    $raw ||= "";
    my $id = $self->id;
    my $bj = $conn->bound_jid;
    my $to = $bj ? (" to='" . $bj->as_string . "'") : "";
    my $xml = qq{<iq $to type='$type' id='$id'>$raw</iq>};
    #warn "About to send IQ reply: $xml\n";
    $conn->write(\$xml);
}

sub process_iq_getroster {
    my ($conn, $iq) = @_;

    # {=getting-roster-on-login}
    $conn->set_requested_roster(1);

    my $send_roster = sub {
        my $roster = shift;
        $logger->info("Sending roster to conn $conn->{id}");
        $iq->send_result_raw($roster->as_xml);
    };

    $conn->run_hook_chain(phase => "RosterGet",
                          methods => {
                              set_roster => sub {
                                  my ($self, $roster) = @_;
                                  $logger->debug("set_roster called in process_iq_getroster");
                                  $send_roster->($roster);
                              },
                          },
                          fallback => sub {
                              $logger->debug("Fallback RosterGet invoked");
                              $send_roster->(DJabberd::Roster->new()),
                          });
    return 1;
}

sub process_iq_setroster {
    my ($conn, $iq) = @_;

    my $item = $iq->query->first_element;
    unless ($item && $item->element eq "{jabber:iq:roster}item") {
        $iq->send_error;
        return;
    }

    # {=xmpp-ip-7.6-must-ignore-subscription-values}
    my $subattr  = $item->attr('{jabber:iq:roster}subscription') || "";
    my $removing = $subattr eq "remove" ? 1 : 0;

    my $jid = $item->attr("{jabber:iq:roster}jid")
        or return $iq->send_error;

    my $name = $item->attr("{jabber:iq:roster}name");

    # find list of group names to add/update.  can ignore
    # if we're just removing.
    my @groups;  # scalars of names
    unless ($removing) {
        foreach my $ele ($item->children_elements) {
            next unless $ele->element eq "{jabber:iq:roster}group";
            push @groups, $ele->first_child;
        }
    }

    my $ritem = DJabberd::RosterItem->new(jid     => $jid,
                                          name    => $name,
                                          remove  => $removing,
                                          groups  => \@groups,
                                          );

    # {=add-item-to-roster}
    my $phase = $removing ? "RosterRemoveItem" : "RosterAddUpdateItem";
    $conn->run_hook_chain(phase   => $phase,
                          args    => [ $ritem ],
                          methods => {
                              done => sub {
                                  my ($self) = @_;
                                  $iq->send_result;
                                  $conn->vhost->roster_push($conn->bound_jid, $ritem);
                              },
                              error => sub {
                                  $iq->send_error;
                              },
                          },
                          fallback => sub {
                              $iq->send_error;
                          });

    return 1;
}

sub process_iq_getauth {
    my ($conn, $iq) = @_;
    # <iq type='get' id='gaimf46fbc1e'><query xmlns='jabber:iq:auth'><username>brad</username></query></iq>

    my $child = $iq->query->first_element
        or return;

    return 0 unless $child->element eq "{jabber:iq:auth}username";

    # force SSL by not letting them login
    if ($conn->vhost->requires_ssl && ! $conn->ssl) {
        $conn->stream_error("policy-violation", "Local policy requires use of SSL before authentication.");
        return;
    }

    my $username = $child->first_child;
    die "Element in username field?" if ref $username;

    my $id = $iq->id;

    my $type = $conn->vhost->are_hooks("GetPassword") ? "<digest/>" : "<password/>";

    $conn->write("<iq id='$id' type='result'><query xmlns='jabber:iq:auth'><username>$username</username>$type<resource/></query></iq>");

    return 1;
}

sub process_iq_setauth {
    my ($conn, $iq) = @_;
    # <iq type='set' id='gaimbb822399'><query xmlns='jabber:iq:auth'><username>brad</username><resource>work</resource><digest>ab2459dc7506d56247e2dc684f6e3b0a5951a808</digest></query></iq>
    my $id = $iq->id;

    my $query = $iq->query
        or die;
    my @children = $query->children;

    my $get = sub {
        my $lname = shift;
        foreach my $c (@children) {
            next unless ref $c && $c->element eq "{jabber:iq:auth}$lname";
            my $text = $c->first_child;
            return undef if ref $text;
            return $text;
        }
        return undef;
    };

    my $username = $get->("username");
    my $resource = $get->("resource");
    my $password = $get->("password");
    my $digest   = $get->("digest");

    return unless $username =~ /^\w+$/;

    my $accept = sub {
        $conn->{authed}   = 1;
        $conn->{username} = $username;
        $conn->{resource} = $resource;

        # register
        my $sname = $conn->server->name;
        my $jid = DJabberd::JID->new("$username\@$sname/$resource");

        $conn->server->register_jid($jid, $conn);
        $conn->set_bound_jid($jid);

        $iq->send_result;
        return;
    };

    my $reject = sub {
        # FIXME: more info?
        $iq->send_reply("error", qq{<error code='401' type='auth'><not-authorized xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error>});
        return 1;
    };

    my $can_get_password = $conn->vhost->are_hooks("GetPassword");

    if ($can_get_password) {
        $conn->run_hook_chain(phase => "GetPassword",
                              args  => [ username => $username, conn => $conn ],
                              methods => {
                                  set => sub {
                                      my (undef, $good_password) = @_;
                                      if ($password && $password eq $good_password) {
                                          $accept->();
                                      } elsif ($digest) {
                                          my $good_dig = Digest::SHA1::sha1_hex($conn->{stream_id} . $good_password);
                                          if ($good_dig eq $digest) {
                                              $accept->();
                                          } else {
                                              $reject->();
                                          }
                                      } else {
                                          $reject->();
                                      }
                                  },
                              },
                              fallback => $reject);
    } else {
        $conn->run_hook_chain(phase => "CheckCleartext",
                              args => [ username => $username, conn => $conn, password => $password ],
                              methods => {
                                  accept => $accept,
                                  reject => $reject,
                              });
    }

    return 1;  # signal that we've handled it
}


sub id {
    return $_[0]->attr("{jabber:client}id");
}

sub type {
    return $_[0]->attr("{jabber:client}type");
}

sub query {
    my $self = shift;
    my $child = $self->first_element
        or return;
    my $ele = $child->element
        or return;
    return undef unless $child->element =~ /\}query$/;
    return $child;
}

1;
