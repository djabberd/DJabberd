package DJabberd::RosterStorage::Dummy;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::RosterStorage';

sub set_config_dummies {
    my ($self, $number) = @_;
    $self->{number} = $number;
}

sub set_config_users {
    my ($self, $users) = @_;
    my @users = split /\s+/, $users;
    $self->{users}->{$_}++ foreach @users;
}

sub finalize {
    my ($self, $vhost ) = @_;
    $self->{number} || 50;
}

sub register {
    my ($self, $vhost) = @_;
    $self->{server_name} = $vhost->server_name;
    $self->SUPER::register($vhost);
}

sub get_roster {
    my ($self, $cb, $jid) = @_;

    my $roster = DJabberd::Roster->new;
    if ($self->{users} && !$self->{users}->{$jid->node} ) {
        $cb->decline;
        return;
    }
    foreach (1..$self->{number}) {
        my $ri =  DJabberd::RosterItem->new(jid => "dummy_$_\@$self->{server_name}" , groups => ["dummies"]);
        $ri->subscription->set_to;
        $ri->subscription->set_from;
        $roster->add($ri);
    }

    $cb->set_roster($roster);
}

1;
