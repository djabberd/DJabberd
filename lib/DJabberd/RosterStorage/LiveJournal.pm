package DJabberd::RosterStorage::LiveJournal;
use strict;
use base 'DJabberd::RosterStorage';
use LWP::Simple;
use Storable;

sub gc {
    return DJabberd::Plugin::LiveJournal->gearman_client;
}

sub get_roster {
    my ($self, $cb, $jid) = @_;

    my $user = $jid->node;
    my $roster = DJabberd::Roster->new;

    my $gc = gc();

    # non-blocking version using gearman
    if ($gc) {
        $gc->add_task(Gearman::Task->new("ljtalk_get_roster" => \ "$user", {
            uniq        => "-",
            retry_count => 2,
            timeout     => 10,
            on_fail     => sub {
                # useful for tracking if not enough workers:  too bad
                # we can't distinguish between timeouts and failures yet.
                $DJabberd::Stats::counter{'ljtalk_get_roster_fail'}++;
                 # which causes an error in vhost.pm's get_roster:
                $cb->decline;
            },
            on_complete => sub {
                my $stref = shift;
                my $list = eval { Storable::thaw($$stref) };
                if ($@) {
                    $cb->decline;
                    return;
                }

                # $list is arrayref of items:
                #      [jid, nick, $substate, [@groups]]
                foreach my $it (@$list) {
                    my $subsc = DJabberd::Subscription->from_bitmask($it->[2]);
                    my $ri = DJabberd::RosterItem->new(jid          => $it->[0],
                                                       name         => $it->[1],
                                                       subscription => $subsc);

                    my $glist = $it->[3];
                    foreach my $grp (@$glist) {
                        $ri->add_group($grp);
                    }
                    $roster->add($ri);
                }

                my $bot = DJabberd::RosterItem->new(jid  => 'lj_bot@' . $jid->domain,
                                                    name => "LJ Bot (Frank)");
                $bot->subscription->set_to;
                # HACK: this is only needed for now because we have no LoadRosterItems plugin that looks
                # up a relation pair in LiveJournal, so if we set this, we get trusted probes for free:
                $bot->subscription->set_from;
                $bot->add_group("LiveJournal");
                $roster->add($bot);

                $cb->set_roster($roster);
                return;
            },
        }));
    }

    # blocking ghetto version w/o gearman:
    else {
        my $friends = LWP::Simple::get("http://www.livejournal.com/misc/fdata.bml?user=" . $user);
        my %relation;  # user -> to (1) / both (2)

        # we depend on all the ">" to edges before the "<" from edges:
        foreach my $line (split(/\r?\n/, $friends)) {
            if ($line =~ /^\> (\w+)/) {
                $relation{$1} = 1;  # to
            } elsif ($line =~ /^\< (\w+)/ && $relation{$1} == 1) {
                $relation{$1} = 2;  # both
            }
        }

        my $domain = $jid->domain;
        foreach my $fuser (sort keys %relation) {
            next if $fuser eq $user;
            my $ri = DJabberd::RosterItem->new(
                                               jid => "$fuser\@$domain",
                                               name => $fuser,
                                               );
            if ($relation{$fuser} == 2) {
                $ri->subscription->set_to;
                $ri->subscription->set_from;
            } else {
                $ri->subscription->set_pending_out;
            }
            $ri->add_group("LiveJournal");
            $roster->add($ri);
        }
        $cb->set_roster($roster);
    }
}

# override this.  unlike addupdate, you should respect the subscription level
sub set_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $self->_addupdateset_item($cb, $jid, $ritem, "respect_sublevel");
}

sub addupdate_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $self->_addupdateset_item($cb, $jid, $ritem, 0);
}

sub _addupdateset_item {
    my ($self, $cb, $jid, $ritem, $opt_usesublevel) = @_;

    my $gc = gc() or
        return $cb->declined;

    my $req = {
        'user'     => $jid->node,
        'contact'  => $ritem->jid->as_bare_string,
        'name'     => $ritem->name,
        'groups'   => [ $ritem->groups ],
        'substate' => $opt_usesublevel ? $ritem->subscription->as_bitmask : undef,
    };
    $req = Storable::nfreeze($req);

    $gc->add_task(Gearman::Task->new("ljtalk_addupdateset_roster" => \$req, {
        uniq        => "-",
        retry_count => 2,
        timeout     => 10,
        on_fail     => sub {
            $DJabberd::Stats::counter{'ljtalk_addupdateset_fail'}++;
            $cb->decline;
        },
        on_complete => sub {
            my $stref = shift;
            my $res = eval { Storable::thaw($$stref) };
            if ($res && defined $res->{substate}) {
                $ritem->set_subscription(DJabberd::Subscription->from_bitmask($res->{substate}));
                $cb->done($ritem);
            } else {
                # Better error method to call?
                $cb->decline;
            }
        },
    }));
}

sub load_roster_item {
    my ($self, $jid, $cjid, $cb) = @_;
    # cb can set($data|undef)' and 'error($reason)

    my $gc = gc() or
        return $cb->declined;

    my $req = Storable::nfreeze({
        'user'     => $jid->node,
        'contact'  => $cjid->as_bare_string,
    });

    $gc->add_task(Gearman::Task->new("ljtalk_load_roster_item" => \$req, {
        uniq        => "-",
        retry_count => 2,
        timeout     => 10,
        on_fail     => sub {
            $DJabberd::Stats::counter{'ljtalk_load_roster_item_fail'}++;
            $cb->error('timeout');
        },
        on_complete => sub {
            my $stref = shift;
            my $res = eval { Storable::thaw($$stref) };
            # we need $res->{'name', 'substate', 'groups'}

            my $ritem =
                DJabberd::RosterItem->new(
                                          jid          => $cjid,
                                          name         => $res->{name},
                                          subscription => DJabberd::Subscription->from_bitmask($res->{substate}),
                                          );
            foreach my $grp (split(/\0/, $res->{groups})) {
                $ritem->add_group($grp);
            }
            $cb->set($ritem);
        },
    }));
}

# override this.
sub delete_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;

    my $gc = gc() or
        return $cb->declined;

    my $req = Storable::nfreeze({
        'user'     => $jid->node,
        'contact'  => $ritem->jid->as_bare_string,
    });

    $gc->add_task(Gearman::Task->new("ljtalk_delete_roster_item" => \$req, {
        uniq        => "-",
        retry_count => 2,
        timeout     => 10,
        on_fail     => sub {
            $DJabberd::Stats::counter{'ljtalk_delete_roster_item_fail'}++;
            $cb->error('timeout');
        },
        on_complete => sub {
            $cb->done;
        },
    }));
}

1;
