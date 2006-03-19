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

sub register {
    my ($self, $vhost) = @_;
    $vhost->register_hook("RosterGet", sub {
        my ($conn, $cb) = @_;
        my $jid = $conn->bound_jid;
        $self->get_roster($cb, $conn, $jid);
    });
}

sub get_roster {
    my ($self, $cb, $conn, $jid) = @_;
    die "NOT IMPLEMENTED BY '$_[0]'.  SUBCLASSES MUST IMPLEMENT.";
}

1;
