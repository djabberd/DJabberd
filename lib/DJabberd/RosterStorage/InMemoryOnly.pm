package DJabberd::RosterStorage::InMemoryOnly;

use strict;
use warnings;
use base 'DJabberd::RosterStorage';

use DJabberd::Log;
use DJabberd::RosterItem;
our $logger = DJabberd::Log->get_logger();

sub finalize {
    my $self = shift;

    $self->{rosters} = {};
    # 'user@local' => {
    #   'contact@remote' => { rosteritem attribs },
    #   ...
    # }

    return $self;
}

sub blocking { 0 }

sub get_roster {
    my ($self, $cb, $jid) = @_;

    $logger->debug("Getting roster for '$jid'");

    my $roster = DJabberd::Roster->new;

    foreach my $item (values %{$self->{rosters}->{$jid} || {}}) {
        my $subscription = DJabberd::Subscription->from_bitmask($item->{subscription});
        $roster->add(DJabberd::RosterItem->new(%$item, subscription => $subscription));
    }

    $logger->debug("  ... got groups, calling set_roster..");

    $cb->set_roster($roster);
}

sub set_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;

    $self->{rosters}->{$jid}->{$ritem->jid} = {
        jid          => $ritem->jid->as_bare_string,
        name         => $ritem->name,
        groups       => [$ritem->groups],
        subscription => $ritem->subscription->as_bitmask,
    };
        
    $logger->debug("Set roster item");
    $cb->done($ritem);
}

sub addupdate_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;

    my $olditem = $self->{rosters}->{$jid}->{$ritem->jid};

    my $newitem = $self->{rosters}->{$jid}->{$ritem->jid} = {
        jid          => $ritem->jid->as_bare_string,
        name         => $ritem->name,
        groups       => [$ritem->groups],
    };

    if (defined $olditem) {
        $ritem->set_subscription(DJabberd::Subscription->from_bitmask($olditem->{subscription}));
        $newitem->{subscription} = $olditem->{subscription};
    }
    else {
        $newitem->{subscription} = $ritem->subscription->as_bitmask;
    }
    
    $cb->done($ritem);
}

sub delete_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $logger->debug("delete roster item!");

    delete $self->{rosters}->{$jid->as_bare_string}->{$ritem->jid};

    $cb->done;
}

sub load_roster_item {
    my ($self, $jid, $contact_jid, $cb) = @_;

    my $options = $self->{rosters}->{$jid->as_bare_string}->{$contact_jid};

    unless (defined $options) {
        $cb->set(undef);
        return;
    }

    my $subscription = DJabberd::Subscription->from_bitmask($options->{subscription});

    my $item = DJabberd::RosterItem->new(%$options, subscription => $subscription);

    $cb->set($item);
    return;
}

sub wipe_roster {
    my ($self, $cb, $jid) = @_;

    delete $self->{rosters}->{$jid->as_bare_string};

    $cb->done;
}

1;
