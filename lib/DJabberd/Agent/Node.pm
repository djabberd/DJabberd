
package DJabberd::Agent::Node;

use base qw(DJabberd::Agent);
use DJabberd::Util qw(exml);
use strict;
use warnings;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub set_config_nodename {
    $_[0]->{agent_node_name} = $_[1];
}

sub finalize {
    $logger->logdie("A node requires a NodeName") unless defined($_[0]->{agent_node_name});
    $_[0]->SUPER::finalize;
}

sub handles_destination {
    my ($self, $to_jid, $vhost) = @_;
    
    return ($to_jid->node eq $self->nodename && $to_jid->domain eq $vhost->server_name);
}

sub name {
    return $_[0]->nodename;
}

sub nodename {
    return $_[0]->{agent_node_name};
}

sub vcard {
    my ($self, $requester_jid) = @_;

    return "<NICKNAME>".exml($self->name)."</NICKNAME>";
}

1;
