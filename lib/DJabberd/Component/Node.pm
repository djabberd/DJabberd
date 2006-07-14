
package DJabberd::Component::Node;

use base qw(DJabberd::Agent::Node);
use DJabberd::Util qw(exml);
use strict;
use warnings;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub set_config_component {
    $_[0]->{component_node_component};
}

sub finalize {
    $logger->logdie("A component node requires a Component") unless ref($_[0]->{component_node_component});
    $_[0]->SUPER::finalize;
}

sub handles_destination {
    my ($self, $to_jid, $vhost) = @_;
    
    return ($to_jid->node eq $self->nodename && $to_jid->domain eq $self->component->domain);
}

sub bare_jid {
    return new DJabberd::JID($_[0]->nodename."@".$_[0]->component->domain);
}

sub resource_jid {
    my ($self, $resourcename) = @_;
    return new DJabberd::JID($self->bare_jid->as_string()."/".$resourcename);
}

sub component {
    return $_[0]->{component_node_component};
}

1;
