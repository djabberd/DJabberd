package DJabberd::RosterStorage::InMemoryOnly;

use strict;
use warnings;
use base 'DJabberd::RosterStorage';

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

sub finalize {
    my $self = shift;

    $self->{rosters} = {};
    # 'user@local' => {
    #   'contact@remote' => DJabberd::RosterItem,
    #   ...
    # }

    return $self;
}

sub blocking { 0 }

sub get_roster {
    my ($self, $cb, $jid) = @_;

    logger->debug("Getting roster for '$jid'");

    my $roster = DJabberd::Roster->new;

    foreach my $item (values %{$self->{rosters}->{$jid} || {}}) {
        $roster->add($item);
    }

    $logger->debug("  ... got groups, calling set_roster..");

    $cb->set_roster($roster);
}

sub set_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $logger->debug("Set roster item");
    $self->addupdate_roster_item($cb, $jid, $ritem);
}

sub addupdate_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    # don't really need to do anything, cause the ritems update themselves in-memory.
    # $self->{rosters}->{$jid}->{$ritem->jid} = $ritem;
    $cb->done($ritem);
}

sub delete_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $logger->debug("delete roster item!");

    delete $self->{rosters}->{$jid}->{$ritem->jid};
    my $dbh  = $self->{dbh};

    $cb->done;
}

sub load_roster_item {
    my ($self, $jid, $contact_jid, $cb) = @_;

    my $item = $self->{rosters}->{$jid}->{$contact_jid};

    $cb->set($item);
    return;
}

sub wipe_roster {
    my ($self, $cb, $jid) = @_;

    delete $self->{rosters}->{$jid};

    $cb->done;
}

1;
