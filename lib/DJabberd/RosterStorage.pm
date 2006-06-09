package DJabberd::RosterStorage;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::Plugin';
use DJabberd::Roster;
use DJabberd::RosterItem;

# don't override, or at least call SUPER to this if you do.
sub register {
    my ($self, $vhost) = @_;
    $vhost->register_hook("RosterGet", sub {
        my ($vh, $cb, $jid) = @_;
        # cb can '->set_roster(Roster)' or decline
        $self->get_roster($cb, $jid);
    });
    $vhost->register_hook("RosterAddUpdateItem", sub {
        my ($vh, $cb, $jid, $ritem) = @_;
        # $cb takes ->done($ritem_final) or error
        $self->addupdate_roster_item($cb, $jid, $ritem);
    });
    $vhost->register_hook("RosterRemoveItem", sub {
        my ($vh, $cb, $jid, $ritem) = @_;
        $self->delete_roster_item($cb, $jid, $ritem);
    });
    $vhost->register_hook("RosterLoadItem", sub {
        my ($vh, $cb, $user_jid, $contact_jid) = @_;
        # cb can 'set($data|undef)' and 'error($reason)'
        $self->load_roster_item($user_jid, $contact_jid, $cb);
    });

    $vhost->register_hook("RosterSetItem", sub {
        my ($vh, $cb, $user_jid, $ritem) = @_;
        # cb can ->error($reason) and ->done()
        $self->set_roster_item($cb, $user_jid, $ritem);
    });
    $vhost->register_hook("RosterWipe", sub {
        my ($vh, $cb, $user_jid) = @_;
        # cb can ->error($reason) and ->done()
        $self->wipe_roster($cb, $user_jid);
    });

}

# override this.
sub get_roster {
    my ($self, $cb, $jid) = @_;
    $cb->declined;
}

# override this.
sub addupdate_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $cb->declined;
}

# override this.  unlike addupdate, you should respect the subscription level
sub set_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    warn "SET ROSTER ITEM FAILED\n";
    $cb->error;
}

# override this.
sub delete_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    $cb->declined;
}

# override this.
sub load_roster_item {
    my ($self, $jid, $target_jid, $cb) = @_;
    $cb->error("load_roster_item not implemented");
}

# override this.
sub wipe_roster {
    my ($self, $cb, $jid) = @_;
    $cb->error("wipe_roster not implemented");
}

1;
