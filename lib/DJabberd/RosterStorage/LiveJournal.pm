package DJabberd::RosterStorage::LiveJournal;
use strict;
use base 'DJabberd::RosterStorage';
use LWP::Simple;
use Storable;

sub blocking { 1 }

sub get_roster {
    my ($self, $cb, $jid) = @_;

    my $user = $jid->node;
    my $roster = DJabberd::Roster->new;

    my $gc = DJabberd::Plugin::LiveJournal->gearman_client;

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

                foreach my $it (@$list) {
                    my $ri = DJabberd::RosterItem->new(jid  => $it->[0],
                                                       name => $it->[1]);
                    my $rels = $it->[2];
                    foreach my $rel (@$rels) {
                        my $meth = "set_$rel";  # set_to, set_from, set_pending_out, etc...
                        $ri->subscription->$meth;
                    }

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

1;
