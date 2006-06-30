package DJabberd::RosterStorage::LiveJournal;
use strict;
use base 'DJabberd::RosterStorage';
use LWP::Simple;

sub blocking { 1 }

sub get_roster {
    my ($self, $cb, $jid) = @_;

    my $user = $jid->node;
    my $roster = DJabberd::Roster->new;

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

1;
