package DJabberd::Plugin::MUC::Room;
use strict;
use warnings;


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{name} = shift;
    $self->{domain} = shift;
    $self->{vhost}  = shift;
    return $self;
}


sub add {
    my ($self, $nickname, $jid) = @_;
    foreach my $member (keys %{$self->{members}}) {
        my $presence = $self->make_response($member);
        $presence->set_to($jid);
        $presence->deliver($self->{vhost});
    }
    $self->{members}->{$nickname} = $jid;
    $self->broadcast($nickname);
}

sub broadcast {
    my ($self, $nickname) = @_;
    warn "broadcastin $nickname";
    foreach my $member (keys %{$self->{members}}) {
        my $presence = $self->make_response($nickname);
        $presence->set_to($self->{members}->{$member});
        $presence->deliver($self->{vhost});

    }
}

sub make_response {
    my ($self, $nickname) = @_;
    my $presence = DJabberd::Presence->new("", 'presence');
    $presence->set_from("$self->{name}\@$self->{domain}/$nickname");
    $presence->set_raw( qq{ <x xmlns='http://jabber.org/protocol/muc#user'><item affiliation='member' role='participant'/></x> });
    return $presence;
}

1;

