
=head1 NAME

DJabberd::Agent::Node - Abstract class for an agent that handles a specific node

=head1 SYNOPSIS

    package MyPackage::DJabberd::MyNode;
    use base DJabberd::Agent::Node;
    
    # Example of an agent that responds to incoming chat messages
    
    sub handle_message {
        my ($self, $vhost, $stanza) = @_;
        
        my $response = $stanza->make_response();
        $response->set_raw("<body>Hello. I'm a software agent.</body>");
        $response->deliver($vhost);
    }

This class provides a parent class for agents which recieve stanzas addressed to
a particular nodename within a domain.

Such an agent is often referred to as a "Bot". A higher-level API for implementing
"chat bots" is also provided in L<DJabberd::Bot|DJabberd::Bot>.

=head1 USAGE

This class is a specialization of L<DJabberd::Agent|DJabberd::Agent>. In most
cases, users of this class will use the API exposed by L<DJabberd::Agent|DJabberd::Agent>.
However, there is some special behaviour to note and some additional methods
that are not part of the basic agent class.

=cut

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

=head2 handles_destination($self, $to_jid, $vhost)

This class provides an overriden version of this method which responds with
a true value if and only if the domain and the nodename of the destination JID
match those that are handled by this instance.

=cut
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

=head2 vcard($self, $requester_jid)

The overriden version of this method will return a vCard where the full name is set
to the nodename of this instance. Subclasses will probably want to override this to
do something more fancy.

=cut
sub vcard {
    my ($self, $requester_jid) = @_;

    return "<NICKNAME>".exml($self->name)."</NICKNAME>";
}

=head1 SEE ALSO

See also L<DJabberd::Agent>, L<DJabberd::Component>.

=head1 COPYRIGHT

Copyright 2007-2008 Martin Atkins

This module is part of the DJabberd distribution and is covered by the distribution's
overall licence.

=cut

1;
