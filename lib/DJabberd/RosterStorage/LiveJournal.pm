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
    foreach my $line (sort split(/\n/, $friends)) {
        next unless $line =~ m!> (\w+)!;
        my $fuser = $1;
        my $ri = DJabberd::RosterItem->new(
                                           jid => "$fuser\@" . $conn->vhost->name,
                                           name => $fuser,
                                           );
        $ri->add_group("LJ Friends");
        $roster->add($ri);
    }
    $cb->set_roster($roster);
}

1;
