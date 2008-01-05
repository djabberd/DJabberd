

=head1 NAME

DJabberd::Component::Node - Specialization of DJabberd::Agent::Node that knows it belongs to a component

=head1 DESCRIPTION

This abstract class is a specialization of L<DJabberd::Agent::Node|DJabberd::Agent::Node>.
The only difference between this class and its parent is that nodes represented by this class
"know" that they belong to a component and have a reference to that component stored.

=head1 SYNOPSIS

Create your node class as a subclass of this class:

    package MyPackage::DJabberd::MyNode;
    use base DJabberd::Component::Node;
    
    # Example of an agent that responds to incoming chat messages
    
    sub handle_message {
        my ($self, $vhost, $stanza) = @_;
        
        my $response = $stanza->make_response();
        $response->set_raw("<body>Hello. I'm a software agent.</body>");
        $response->deliver($vhost);
    }

The class can then be instantiated from inside a method in a L<DJabberd::Component|DJabberd::Component> instance:

    # $self here is a DJabberd::Component object
    my $node = MyPackage::DJabberd::MyNode->new(
        component => $self,
        nodename => "bob",
    );

The above created instance will accept stanzas addressed to the node "bob" inside the domain owned
by the given component.

It is not possible to directly use subclasses of this class as delivery plugins, since they
must be associated with a component at runtime.

=cut

package DJabberd::Component::Node;

use base qw(DJabberd::Agent::Node);
use DJabberd::Util qw(exml);
use strict;
use warnings;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub set_config_component {
    $_[0]->{component_node_component} = $_[1];
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

=head1 SEE ALSO

See also L<DJabberd::Agent::Node>, L<DJabberd::Component>.

=head1 COPYRIGHT

Copyright 2007-2008 Martin Atkins

This module is part of the DJabberd distribution and is covered by the distribution's
overall licence.

=cut
1;
