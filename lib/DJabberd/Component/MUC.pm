
package DJabberd::Component::MUC;

use base 'DJabberd::Component';
use strict;
use DJabberd::Log;
use DJabberd::Component::MUC::Room;
use DJabberd::Util qw(exml);

our $logger = DJabberd::Log->get_logger();

sub set_config_displayname {
    my ($self, $name) = @_;
    
    $self->{component_muc_displayname} = $name;
}

sub finalize {
    my ($self) = @_;
    
    $self->{component_muc_activerooms} = { 'test' => DJabberd::Component::MUC::Room->new(nodename => 'text', component => $self) };
    
    $self->SUPER::finalize;
}

sub get_node {
    my ($self, $nodename) = @_;

    
    return $self->{component_muc_activerooms}{$nodename} if $self->{component_muc_activerooms}{$nodename};
    return $self->get_room($nodename);
}

sub get_room {
    my ($self, $name) = @_;
    
    return DJabberd::Component::MUC::Room->new(nodename => $name, component => $self);
}

sub name {
    return $_[0]->{component_muc_displayname} || $_[0]->SUPER::name;
}

sub identities {
    my ($self) = @_;
    
    return [
        [ 'conference', 'text', $self->name ],
    ];
}

sub features {
    my ($self) = @_;
    
    return [ "http://jabber.org/protocol/muc", @{$self->SUPER::features} ];
}

sub room_jid {
    my ($self, $roomname) = @_;
    
    return new DJabberd::JID($roomname.'@'.$self->domain);
}

sub child_services {
    my ($self, $requester_jid) = @_;
    
    my $rooms = $self->get_visible_rooms($requester_jid);

    return [ map {
        [ $_->[0]."@".$self->domain, "$_->[1]" ],
    } @$rooms ];
}

sub get_visible_rooms {
    my ($self, $requester_jid) = @_;
    
    return [ map {
        [ $_, $self->{component_muc_activerooms}{$_}->name ]
    } sort keys %{$self->{component_muc_activerooms}} ];
}

1;
