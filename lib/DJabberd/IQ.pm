package DJabberd::IQ;
use strict;
use base qw(DJabberd::Stanza);

sub process {
    my ($self, $conn) = @_;

    my $handler = {
        'get-{jabber:iq:roster}query' => \&process_iq_getroster,
        'get-{jabber:iq:auth}query' => \&process_iq_getauth,
        'set-{jabber:iq:auth}query' => \&process_iq_setauth,
    };

    $conn->run_hook_chain(phase    => "c2s-iq",
                          args     => [ $self ],
                          fallback => sub {
                              my $sig = $self->signature;
                              my $meth = $handler->{$sig};
                              unless ($meth) {
                                  warn "Unknown IQ packet: $sig";
                                  return;
                              }
                              $meth->($conn, $self);
                          });
}

sub signature {
    my $iq = shift;
    my $fc = $iq->first_child;
    # FIXME: should signature ever get called on a bogus IQ packet?
    return $iq->type . "-" . ($fc ? $fc->element : "(BOGUS)");
}

sub process_iq_getroster {
    my ($conn, $iq) = @_;

    my $to = $conn->jid;
    my $id = $iq->id;

    my $send_roster = sub {
        my $body = shift;
        my $roster_res = qq{
            <iq to='$to' type='result' id='$id'>
                <query xmlns='jabber:iq:roster'>
                $body
                </query>
                </iq>
            };
        $conn->write($roster_res);
    };

    $conn->run_hook_chain(phase => "getroster",
                          args => [ $iq ],
                          methods => {
                              set_roster_body => sub {
                                  my ($self, $body) = @_;
                                  $send_roster->($body);
                              },
                          },
                          fallback => sub {
                              $send_roster->("<item jid='xxxxx\@example.com' name='XXXXXXXXX' subscription='both'><group>Friends</group></item>\n");

                          });
    return 1;
}

sub process_iq_getauth {
    my ($conn, $iq) = @_;
    # <iq type='get' id='gaimf46fbc1e'><query xmlns='jabber:iq:auth'><username>brad</username></query></iq>

    my $child = $iq->query->first_element
        or return;

    return 0 unless $child->element eq "{jabber:iq:auth}username";

    my $username = $child->first_child;
    die "Element in username field?" if ref $username;

    my $id = $iq->id;

    $conn->write("<iq id='$id' type='result'><query xmlns='jabber:iq:auth'><username>$username</username><digest/><resource/></query></iq>");

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
    my $digest   = $get->("digest");

    return unless $username =~ /^\w+$/;

    my $accept = sub {
        $conn->{authed}   = 1;
        $conn->{username} = $username;
        $conn->{resource} = $resource;

        # register
        my $sname = $conn->server->name;
        foreach my $jid ("$username\@$sname",
                         "$username\@$sname/$resource") {
            $conn->server->register_jid($jid, $conn);
        }

        # FIXME: escape, or make $iq->send_good_result, or something
        $conn->write(qq{<iq id='$id' type='result' />});
        return;
    };

    my $reject = sub {
        warn " BAD LOGIN!\n";
        # FIXME: FAIL
        return 1;
    };

    $conn->run_hook_chain(phase => "Auth",
                          args  => [ { username => $username, resource => $resource, digest => $digest } ],
                          methods => {
                              accept => $accept,
                              reject => $reject,
                          },
                          fallback => $reject);

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
