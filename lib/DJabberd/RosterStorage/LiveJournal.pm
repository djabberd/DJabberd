package DJabberd::RosterStorage::LiveJournal;
use strict;
use base 'DJabberd::RosterStorage';
use LWP::Simple;

sub blocking { 1 }

sub get_roster {
    my ($self, $cb, $conn, $jid) = @_;

    my $user = $jid->node;
    my $roster = DJabberd::Roster->new;

    my $friends = LWP::Simple::get("http://www.livejournal.com/misc/fdata.bml?user=" . $user);
    my %relation;  # user -> to (1) / both (2)

    # we depend on all the ">" to edges before the "<" from edges:
    foreach my $line (sort split(/\n/, $friends)) {
        if ($line =~ m!> (\w+)!) {
            $relation{$1} = 1;  # to
        } elsif ($line =~ m!< (\w+)! && $relation{$1} == 1) {
            $relation{$1} = 2;  # both
        }
    }

    foreach my $user (sort keys %relation) {
        my $ri = DJabberd::RosterItem->new(
                                           jid => "$user\@" . $conn->vhost->name,
                                           name => $user,
                                           );
        $ri->subscription->set_to;
        if ($relation{$user} == 2) {
            $ri->subscription->set_from;
        }
        $ri->add_group("LiveJournal");
        $roster->add($ri);
    }

    $cb->set_roster($roster);
}

1;
