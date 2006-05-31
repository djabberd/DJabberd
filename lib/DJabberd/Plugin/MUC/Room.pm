
package DJabberd::Plugin::MUC::Room;
use strict;
use warnings;


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{name} = shift;
    $self->{domain} = shift;
    $self->{vhost}  = shift;
    Scalar::Util::weaken($self->{vhost});
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
    $self->{jid2nick}->{$jid}     = $nickname;
    $self->broadcast($nickname);
}

sub broadcast {
    my ($self, $nickname) = @_;
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

sub send_message {
    my ($self, $stanza) = @_;
    my $message_template = $stanza->clone;
    my $nickname = $self->{jid2nick}->{$stanza->from} || die "User @{[$stanza->from]} is not a member of room $self->{name}";
    $message_template->set_from("$self->{name}\@$self->{domain}/$nickname");
    foreach my $member (keys %{$self->{members}}) {
        my $message = $message_template->clone;
        $message->set_to($self->{members}->{$member});
        $message->deliver($self->{vhost});
    }
}

1;

