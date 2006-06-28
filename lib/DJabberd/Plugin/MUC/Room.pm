
package DJabberd::Plugin::MUC::Room;
use strict;
use warnings;
use Carp;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{name} = shift;
    $self->{domain} = shift;
    $self->{vhost}  = shift;
    Scalar::Util::weaken($self->{vhost});
    return $self;
}

sub new_from_config {
    my ($class, $name, $domain, $vhost, $arg) = @_;

    croak "DJabberd::Plugin::MUC::Room takes no arguments" if $arg;

    return $class->new($name, $domain, $vhost);
}

sub add {
    my ($self, $nickname, $jid) = @_;

    return if exists $self->{members}->{$nickname};

    if (exists $self->{jid2nick}->{$jid}) {
        my $old_nickname = $self->{jid2nick}->{$jid};
        # rename nick
        foreach my $member (keys %{$self->{members}}) {
            my $presence = $self->make_response($old_nickname, "unavailable");
            $presence->set_raw( qq{ <x xmlns='http://jabber.org/protocol/muc#user'>   <item affiliation='member'
                                        jid='$jid'
                                        nick='$nickname'
                                        role='participant'/>
                                        <status code='303'/></x> });
            $presence->set_to($self->{members}->{$member});

            $presence->deliver($self->{vhost});
        }
         delete $self->{members}->{$old_nickname};
         delete $self->{jid2nick}->{$jid};
    }


    foreach my $member (keys %{$self->{members}}) {
        my $presence = $self->make_response($member);
        $presence->set_to($jid);
        $presence->deliver($self->{vhost});
    }
    $self->{members}->{$nickname} = $jid;
    $self->{jid2nick}->{$jid}     = $nickname;
    $self->broadcast($nickname);
}

sub remove {
    my ($self, $nickname, $jid) = @_;
    delete $self->{members}->{$nickname};
    delete $self->{jid2nick}->{$jid};
    $self->broadcast($nickname, "unavailable");
}

sub broadcast {
    my ($self, $nickname ,$type) = @_;
    foreach my $member (keys %{$self->{members}}) {
        my $presence = $self->make_response($nickname, $type);
        $presence->set_to($self->{members}->{$member});
        $presence->deliver($self->{vhost});

    }
}

sub make_response {
    my ($self, $nickname, $type) = @_;
    my $presence = DJabberd::Presence->new("", 'presence');
    $presence->set_from("$self->{name}\@$self->{domain}/$nickname");
    $presence->attrs->{"{}type"} = $type if ($type);
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

