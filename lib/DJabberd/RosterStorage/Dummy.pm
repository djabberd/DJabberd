package DJabberd::RosterStorage::Dummy;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::RosterStorage';

sub get_roster {
    my ($self, $cb, $conn, $jid) = @_;

    my $roster = DJabberd::Roster->new;
    $roster->add(DJabberd::RosterItem->new('crucially@jabber.bradfitz.com'));
    $roster->add(DJabberd::RosterItem->new('brad@jabber.bradfitz.com'));

    $cb->set_roster($roster);
}

1;
