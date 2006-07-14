
package DJabberd::Component::Node;

use base qw(DJabberd::Agent);
use DJabberd::Util qw(exml);
use strict;
use warnings;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub set_config_nodename {
    $_[0]->{component_node_name};
}

sub set_config_component {
    $_[0]->{component_node_component};
}

sub finalize {
    $logger->logdie("A node requires a NodeName") unless defined($_[0]->{component_node_name});
    $logger->logdie("A node requires a Component") unless ref($_[0]->{component_node_component});
}

sub handles_destination {
    my ($self, $to_jid, $vhost) = @_;
    
    return ($to_jid->node eq $self->nodename && $to_jid->domain eq $self->component->domain);
}

sub name {
    return $_[0]->nodename;
}

sub nodename {
    return $_[0]->{component_node_name};
}

sub bare_jid {
    return new DJabberd::JID($_[0]->{component_node_name}."@".$_[0]->{component_node_component}->domain);
}

sub resource_jid {
    my ($self, $resourcename) = @_;
    return new DJabberd::JID($self->bare_jid->as_string()."/".$resourcename);
}

sub component {
    return $_[0]->{component_node_component};
}

sub vcard {
    my ($self, $requester_jid) = @_;

    # Empty vCard by default
    return "<NICKNAME>".exml($self->name)."</NICKNAME>";
}

1;
