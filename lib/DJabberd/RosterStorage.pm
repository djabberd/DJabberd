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
        my $jid = $conn->bound_jid;
        $self->get_roster($cb, $conn, $jid);
    });
    $vhost->register_hook("RosterSetItem", sub {
        my ($conn, $cb, $ritem) = @_;
        my $jid = $conn->bound_jid;
        $self->set_roster_item($cb, $conn, $jid, $ritem);
    });
    $vhost->register_hook("RosterRemoveItem", sub {
        my ($conn, $cb, $ritem) = @_;
        my $jid = $conn->bound_jid;
        $self->delete_roster_item($cb, $conn, $jid, $ritem);
    });
}

# override this.
sub get_roster {
    my ($self, $cb, $conn, $jid) = @_;
    $cb->declined;
}

# override this.
sub set_roster_item {
    my ($self, $cb, $conn, $jid, $ritem) = @_;
    $cb->declined;
}

# override this.
sub delete_roster_item {
    my ($self, $cb, $conn, $jid, $ritem) = @_;
    $cb->declined;
}

1;
