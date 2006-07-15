
package DJabberd::Component::MUC::Participant;

# FIXME: This should probably be a subclass of some other class
#    that represents full JIDs rather than bare JIDs.
use base qw(DJabberd::Component::Node);
use DJabberd::Util qw(exml);
use strict;
use warnings;
use DJabberd::Log;
use DJabberd::JID;

our $logger = DJabberd::Log->get_logger();

sub set_config_room {
    my ($self, $room) = @_;
    
    $self->{component_muc_participant_room} = $room;
}

sub set_config_nickname {
    my ($self, $nickname) = @_;
    
    $self->{component_muc_participant_nickname} = $nickname;
}

sub set_config_jid {
    my ($self, $jid) = @_;
    
    $self->{component_muc_participant_jid} = $jid;
}

sub finalize {
    my ($self) = @_;
    
    $logger->logdie("No Room given") unless ref $self->{component_muc_participant_room};
    $logger->logdie("No Nickname given") unless $self->{component_muc_participant_nickname};
    $logger->logdie("No JID given") unless ref $self->{component_muc_participant_jid};
    
    $logger->debug("Created participant ".$self->nickname." in room ".$self->room->nodename);
    
    $self->SUPER::finalize;
}

sub room {
    return $_[0]->{component_muc_participant_room};
}
sub nickname {
    return $_[0]->{component_muc_participant_nickname};
}
sub real_jid {
    return $_[0]->{component_muc_participant_jid};
}

sub apparent_jid {
    my ($self) = @_;
    
    return $self->room->resource_jid($self->nickname);
}

sub role {
    return "participant";
}

sub affiliation {
    return "member";
}

sub send_presence {
    my ($self, $to_jid, $status, $type) = @_;
    
    my $presence = new DJabberd::Presence(
        'jabber:server',
        'presence',
        {
            '{}from' => $self->apparent_jid,
            '{}to' => $to_jid
        },
        [],
    );
    
    $presence->attrs->{"{}type"} = $type if $type;
    
    $presence->set_raw(
        "<x xmlns='http://jabber.org/protocol/muc#user'>".
        "<item affiliation='".exml($self->affiliation)."' role='".exml($self->role)."'/>".
        ($status ? "<status code='".exml($status)."'>" : "").
        "</x>"
    );

    $self->room->send_stanza($presence);
}

1;
