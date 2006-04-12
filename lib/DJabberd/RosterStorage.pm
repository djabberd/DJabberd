package DJabberd::RosterStorage;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::Plugin';
use DJabberd::Roster;
use DJabberd::RosterItem;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

# don't override, or at least call SUPER to this if you do.
sub register {
    my ($self, $vhost) = @_;
    $vhost->register_hook("RosterGet", sub {
        my ($conn, $cb) = @_;
        # cb can '->set_roster(Roster)' or decline
        my $jid = $conn->bound_jid;
        $self->get_roster($cb, $jid);
    });
    $vhost->register_hook("RosterAddUpdateItem", sub {
        my ($conn, $cb, $ritem) = @_;
        my $jid = $conn->bound_jid;
        $self->addupdate_roster_item($cb, $jid, $ritem);
    });
    $vhost->register_hook("RosterRemoveItem", sub {
        my ($conn, $cb, $ritem) = @_;
        my $jid = $conn->bound_jid;
        $self->delete_roster_item($cb, $jid, $ritem);
    });
    $vhost->register_hook("RosterLoadItem", sub {
        my ($conn, $cb, $user_jid, $contact_jid) = @_;
        # cb can 'set($data|undef)' and 'error($reason)'
        $self->load_roster_item($user_jid, $contact_jid, $cb);
    });

    $vhost->register_hook("RosterSetItem", sub {
        my (undef, $cb, $user_jid, $ritem) = @_;
        # cb can ->error($reason) and ->done()
        $self->set_roster_item($cb, $user_jid, $ritem);
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

1;
