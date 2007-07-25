package DJabberd::IQ;
use strict;
use base qw(DJabberd::Stanza);
use DJabberd::Util qw(exml);
use DJabberd::Roster;

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

sub on_recv_from_client {
    my ($self, $conn) = @_;

    my $to = $self->to_jid;
    if (! $to || $conn->vhost->uses_jid($to)) {
        $self->process($conn);
        return;
    }

    $self->deliver;
}

my $iq_handler = {
    'get-{jabber:iq:roster}query' => \&process_iq_getroster,
    'set-{jabber:iq:roster}query' => \&process_iq_setroster,
    'get-{jabber:iq:auth}query' => \&process_iq_getauth,
    'set-{jabber:iq:auth}query' => \&process_iq_setauth,
    'get-{http://jabber.org/protocol/disco#info}query'  => \&process_iq_disco_info_query,
    'get-{http://jabber.org/protocol/disco#items}query' => \&process_iq_disco_items_query,
    'get-{jabber:iq:register}query' => \&process_iq_getregister,
    'set-{jabber:iq:register}query' => \&process_iq_setregister,
    'set-{djabberd:test}query' => \&process_iq_set_djabberd_test,
};

# DO NOT OVERRIDE THIS
sub process {
    my DJabberd::IQ $self = shift;
    my $conn = shift;

    # FIXME: handle 'result'/'error' IQs from when we send IQs
    # out, like in roster pushes

    # Trillian Jabber 3.1 is stupid and sends a lot of IQs (but non-important ones)
    # without ids.  If we respond to them (also without ids, or with id='', rather),
    # then Trillian crashes.  So let's just ignore them.
    return unless defined($self->id) && length($self->id);

    $conn->vhost->run_hook_chain(phase    => "c2s-iq",
                                 args     => [ $self ],
                                 fallback => sub {
                                     my $sig = $self->signature;
                                     my $meth = $iq_handler->{$sig};
                                     unless ($meth) {
                                         $self->send_error(
                                            qq{<error type='cancel'>}.
                                            qq{<feature-not-implemented xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>}.
                                            qq{<text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas' xml:lang='en'>}.
                                            qq{This feature is not implemented yet in DJabberd.}.
                                            qq{</text>}.
                                            qq{</error>}
                                         );
                                         $logger->warn("Unknown IQ packet: $sig");
                                         return;
                                     }

                                     $DJabberd::Stats::counter{"InIQ:$sig"}++;
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
    my $raw = shift || '';
    $self->send_reply("error", $self->innards_as_xml . "\n" . $raw);
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
    my $from_jid = $self->to;
    my $to = $bj ? (" to='" . $bj->as_string_exml . "'") : "";
    my $from = $from_jid ? (" from='" . $from_jid . "'") : "";
    my $xml = qq{<iq$to$from type='$type' id='$id'>$raw</iq>};
    $conn->xmllog->info($xml);
    $conn->write(\$xml);
}

sub process_iq_disco_info_query {
    my ($conn, $iq) = @_;

    # Trillian, again, is fucking stupid and crashes on just
    # about anything its homemade XML parser doesn't like.
    # so ignore it when it asks for this, just never giving
    # it a reply.
    if ($conn->vhost->quirksmode && $iq->id =~ /^trill_/) {
        return;
    }

    # TODO: these can be sent back to another server I believe -- sky

    # TODO: Here we need to figure out what identities we have and
    # capabilities we have
    my $xml;
    $xml  = qq{<query xmlns='http://jabber.org/protocol/disco#info'>};
    $xml .= qq{<identity category='server' type='im' name='djabberd'/>};

    foreach my $cap ('http://jabber.org/protocol/disco#info',
                     $conn->vhost->features)
    {
        $xml .= "<feature var='$cap'/>";
    }
    $xml .= qq{</query>};

    $iq->send_reply('result', $xml);
}

sub process_iq_disco_items_query {
    my ($conn, $iq) = @_;

    my $vhost = $conn->vhost;

    my $items = $vhost ? $vhost->child_services : {};

    my $xml = qq{<query xmlns='http://jabber.org/protocol/disco#items'>}.
        join('', map({ "<item jid='".exml($_)."' name='".exml($items->{$_})."' />" } keys %$items)).
        qq{</query>};

    $iq->send_reply('result', $xml);
}

sub process_iq_getroster {
    my ($conn, $iq) = @_;

    my $send_roster = sub {
        my $roster = shift;
        $logger->info("Sending roster to conn $conn->{id}");
        $iq->send_result_raw($roster->as_xml);

        # JIDs who want to subscribe to us, since we were offline
        foreach my $jid (map  { $_->jid }
                         grep { $_->subscription->pending_in }
                         $roster->items) {
            my $subpkt = DJabberd::Presence->make_subscribe(to   => $conn->bound_jid,
                                                            from => $jid);
            # already in roster as pendin, we've already processed it,
            # so just deliver it (or queue it) so user can reply with
            # subscribed/unsubscribed:
            $conn->note_pend_in_subscription($subpkt);
        }
    };

    # need to be authenticated to request a roster.
    my $bj = $conn->bound_jid;
    unless ($bj) {
        $iq->send_error(
            qq{<error type='auth'>}.
            qq{<not-authorized xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>}.
            qq{<text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas' xml:lang='en'>}.
            qq{You need to be authenticated before requesting a roster.}.
            qq{</text>}.
            qq{</error>}
        );
        return;
    }

    # {=getting-roster-on-login}
    $conn->set_requested_roster(1);

    $conn->vhost->get_roster($bj,
                             on_success => $send_roster,
                             on_fail => sub {
                                 $send_roster->(DJabberd::Roster->new);
                             });

    return 1;
}

sub process_iq_setroster {
    my ($conn, $iq) = @_;

    my $item = $iq->query->first_element;
    unless ($item && $item->element eq "{jabber:iq:roster}item") {
        $iq->send_error( # TODO make this error proper
            qq{<error type='error-type'>}.
            qq{<not-authorized xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>}.
            qq{<text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas' xml:lang='langcode'>}.
            qq{You need to be authenticated before requesting a roster.}.
            qq{</text>}.
            qq{</error>}
        );
        return;
    }

    # {=xmpp-ip-7.6-must-ignore-subscription-values}
    my $subattr  = $item->attr('{}subscription') || "";
    my $removing = $subattr eq "remove" ? 1 : 0;

    my $jid = $item->attr("{}jid")
        or return $iq->send_error( # TODO Yeah, this one too
            qq{<error type='error-type'>}.
            qq{<not-authorized xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>}.
            qq{<text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas' xml:lang='langcode'>}.
            qq{You need to be authenticated before requesting a roster.}.
            qq{</text>}.
            qq{</error>}
        );

    my $name = $item->attr("{}name");

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

    # TODO if ($removing), send unsubscribe/unsubscribed presence
    # stanzas.  See RFC3921 8.6

    # {=add-item-to-roster}
    my $phase = $removing ? "RosterRemoveItem" : "RosterAddUpdateItem";
    $conn->vhost->run_hook_chain(phase   => $phase,
                                 args    => [ $conn->bound_jid, $ritem ],
                                 methods => {
                                     done => sub {
                                         my ($self, $ritem_final) = @_;

                                         # the RosterRemoveItem isn't required to return the final item
                                         $ritem_final = $ritem if $removing;

                                         $iq->send_result;
                                         $conn->vhost->roster_push($conn->bound_jid, $ritem_final);

                                         # TODO: section 8.6: must send a
                                         # bunch of presence
                                         # unsubscribe/unsubscribed messages
                                     },
                                     error => sub { # TODO What sort of error stat is being hit here?
                                         $iq->send_error;
                                     },
                                 },
                                 fallback => sub {
                                     if ($removing) {
                                         # NOTE: we used to send an error here, but clients get
                                         # out of sync and we need to let them think a delete
                                         # happened even if it didn't.
                                         $iq->send_result;
                                     } else { # TODO ACK, This one as well
                                         $iq->send_error;
                                     }
                                 });

    return 1;
}

sub process_iq_getregister {
    my ($conn, $iq) = @_;

    # If the entity is not already registered and the host supports
    # In-Band Registration, the host MUST inform the entity of the
    # required registration fields. If the host does not support
    # In-Band Registration, it MUST return a <service-unavailable/>
    # error. If the host is redirecting registration requests to some
    # other medium (e.g., a website), it MAY return an <instructions/>
    # element only, as shown in the Redirection section of this
    # document.
    my $vhost = $conn->vhost;
    unless ($vhost->allow_inband_registration) {
        # MUST return a <service-unavailable/>
        $iq->send_error(
            qq{<error type='cancel' code='503'>}.
            qq{<service-unavailable xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>}.
            qq{<text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas' xml:lang='en'>}.
            qq{In-Band registration is not supported by this server's configuration.}.
            qq{</text>}.
            qq{</error>}
        );
        return;
    }

    # if authenticated, give them existing login info:
    if (my $jid = $conn->bound_jid) {

        my $password = 0 ? "<password></password>" : "";  # TODO
        my $username = $jid->node;
        $iq->send_result_raw(qq{<query xmlns='jabber:iq:register'>
                                    <registered/>
                                    <username>$username</username>
                                    $password
                                    </query>});
        return;
    }

    # not authenticated, ask for their required fields
    # NOTE: we send_result_raw here, which just writes, so they don't
    # need to be an available resource (since they're not even authed
    # yet) for this to work.  that's like most things in IQ anyway.
    $iq->send_result_raw(qq{<query xmlns='jabber:iq:register'>
                                <instructions>
                                Choose a username and password for use with this service.
                                </instructions>
                                <username/>
                                <password/>
                                </query>});
}

sub process_iq_setregister {
    my ($conn, $iq) = @_;

    my $vhost = $conn->vhost;
    unless ($vhost->allow_inband_registration) {
        # MUST return a <service-unavailable/>
        $iq->send_error(
            qq{<error type='cancel'>}.
            qq{<service-unavailable xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>}.
            qq{<text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas' xml:lang='en'>}.
            qq{In-Band registration is not supported by this server\'s configuration.}.
            qq{</text>}.
            qq{</error>}
        );
        return;
    }

    my $bjid = $conn->bound_jid;

    # remove (cancel) support
    my $item = $iq->query->first_element;
    if ($item && $item->element eq "{jabber:iq:register}remove") {
        if ($bjid) {
            my $rosterwipe = sub {
                $vhost->run_hook_chain(phase => "RosterWipe",
                                       args => [ $bjid ],
                                       methods => {
                                           done => sub {
                                               $iq->send_result;
                                               $conn->stream_error("not-authorized");
                                           },
                                       });
            };

            $vhost->run_hook_chain(phase => "UnregisterJID",
                                   args => [ username => $bjid->node, conn => $conn ],
                                   methods => {
                                       deleted => sub {
                                           $rosterwipe->();
                                       },
                                       notfound => sub {
                                           warn "notfound.\n";
                                           return $iq->send_error;
                                       },
                                       error => sub {
                                           return $iq->send_error;
                                       },
                                   });

            $iq->send_result;
        } else {
            $iq->send_error; # TODO: <forbidden/>
        }
        return;
    }

    my $query = $iq->query
        or die;
    my @children = $query->children;
    my $get = sub {
        my $lname = shift;
        foreach my $c (@children) {
            next unless ref $c && $c->element eq "{jabber:iq:register}$lname";
            my $text = $c->first_child;
            return undef if ref $text;
            return $text;
        }
        return undef;
    };

    my $username = $get->("username");
    my $password = $get->("password");
    return $iq->send_error unless $username =~ /^\w+$/;
    return $iq->send_error if $bjid && $bjid->node ne $username;

    # create the account
    $vhost->run_hook_chain(phase => "RegisterJID",
                           args => [ username => $username, conn => $conn, password => $password ],
                           methods => {
                               saved => sub {
                                   return $iq->send_result;
                               },
                               conflict => sub {
                                   my $epass = exml($password);
                                   return $iq->send_error(qq{
                                       <query xmlns='jabber:iq:register'>
                                           <username>$username</username>
                                           <password>$epass</password>
                                           </query>
                                           <error code='409' type='cancel'>
                                           <conflict xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>
                                           </error>
                                       });
                               },
                               error => sub {
                                   return $iq->send_error;
                               },
                           });

}


sub process_iq_getauth {
    my ($conn, $iq) = @_;
    # <iq type='get' id='gaimf46fbc1e'><query xmlns='jabber:iq:auth'><username>brad</username></query></iq>

    # force SSL by not letting them login
    if ($conn->vhost->requires_ssl && ! $conn->ssl) {
        $conn->stream_error("policy-violation", "Local policy requires use of SSL before authentication.");
        return;
    }

    my $username = "";
    my $child = $iq->query->first_element;
    if ($child && $child->element eq "{jabber:iq:auth}username") {
        $username = $child->first_child;
        die "Element in username field?" if ref $username;
    }

    # FIXME:  use nodeprep or whatever, not \w+
    $username = '' unless $username =~ /^\w+$/;

    my $type = ($conn->vhost->are_hooks("GetPassword") ||
                $conn->vhost->are_hooks("CheckDigest")) ? "<digest/>" : "<password/>";

    $iq->send_result_raw("<query xmlns='jabber:iq:auth'><username>$username</username>$type<resource/></query>");
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

    my $vhost = $conn->vhost;

    my $reject = sub {
        $DJabberd::Stats::counter{'auth_failure'}++;
        $iq->send_reply("error", qq{<error code='401' type='auth'><not-authorized xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error>});
        return 1;
    };


    my $accept = sub {
        # register
        my $sname = $vhost->name;
        my $jid = DJabberd::JID->new("$username\@$sname/$resource");

        unless ($jid) {
            $reject->();
            return;
        }

        my $regcb = DJabberd::Callback->new({
            registered => sub {
                $conn->set_bound_jid($jid);
                $DJabberd::Stats::counter{'auth_success'}++;
                $iq->send_result;
            },
            error => sub {
                $iq->send_error;
            },
            _post_fire => sub {
                $conn = undef;
                $iq   = undef;
            },
        });

        $vhost->register_jid($jid, $conn, $regcb);
    };

    my $can_get_password = $vhost->are_hooks("GetPassword");

    if ($can_get_password) {
        $vhost->run_hook_chain(phase => "GetPassword",
                              args  => [ username => $username, conn => $conn ],
                              methods => {
                                  set => sub {
                                      my (undef, $good_password) = @_;
                                      if ($password && $password eq $good_password) {
                                          $accept->();
                                      } elsif ($digest) {
                                          my $good_dig = lc(Digest::SHA1::sha1_hex($conn->{stream_id} . $good_password));
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
    } elsif ($vhost->are_hooks("CheckDigest")) {
        $vhost->run_hook_chain(phase => "CheckDigest",
                              args => [ username => $username, conn => $conn, digest => $digest, resource => $resource ],
                              methods => {
                                  accept => $accept,
                                  reject => $reject,
                              });
    } else {
        $vhost->run_hook_chain(phase => "CheckCleartext",
                              args => [ username => $username, conn => $conn, password => $password ],
                              methods => {
                                  accept => $accept,
                                  reject => $reject,
                              });
    }

    return 1;  # signal that we've handled it
}

sub process_iq_set_djabberd_test {
    my ($conn, $iq) = @_;
    # <iq type='set' id='foo'><query xmlns='djabberd:test'>some command</query></iq>
    my $id = $iq->id;

    unless ($ENV{DJABBERD_TEST_COMMANDS}) {
        $iq->send_error;
        return;
    }

    my $query = $iq->query
        or die;
    my $command = $query->first_child;

    if ($command eq "write error") {
        $conn->set_writer_func(sub {
            my ($bref, $to_write, $offset) = @_;
            $conn->close;
            return 0;
        });
        $iq->send_result_raw("<wont_get_to_you_anyway/>");
        return;
    }

    $iq->send_result_raw("<unknown-command/>");
}

sub id {
    return $_[0]->attr("{}id");
}

sub type {
    return $_[0]->attr("{}type");
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

sub deliver_when_unavailable {
    my $self = shift;
    return $self->type eq "result" ||
        $self->type eq "error";
}

sub make_response {
    my ($self) = @_;

    my $response = $self->SUPER::make_response();
    $response->attrs->{"{}type"} = "result";
    return $response;
}

1;
