
=head1 NAME

DJabberd::Component - Abstract class representing a component in DJabberd

=head1 SYNOPSIS

    package MyPackage::DJabberd::MyComponent;
    use base DJabberd::Component;
    
    # Example of a component which accepts XEP-0050 Ad-Hoc Commands
    
    sub finalize {
        my ($self, $opts) = @_;
        
        # Let the parent class finalize
        $self->SUPER::finalize;
        
        $self->register_iq_handler(
            "set-{http://jabber.org/protocol/commands}command",
            sub { $self->handle_adhoc_command(@_) },
        );
    }
    
    sub handle_adhoc_command {
        my ($self, $vhost, $stanza) = @_;
        
        # handle the DJabberd::IQ stanza in $stanza,
        # or send some kind of error response.
    }

This class provides a parent class for all DJabberd components. Components
that inherit from this class can then be used directly by the server as delivery plugins,
or used directly by other classes.

See L<DJabberd::Component::Example> for an example component implementation.

=head1 USAGE

This class is a specialization of L<DJabberd::Agent|DJabberd::Agent> which is aimed
at those wishing to create "components", which are software agents that handle
an entire XMPP domain, including all of the nodes within that domain.

In most cases, users of this class will use the API exposed by L<DJabberd::Agent|DJabberd::Agent>.
However, there is some special behaviour to note and some additional methods
that are not part of the basic agent class.

=cut

package DJabberd::Component;

use base 'DJabberd::Agent';
use strict;
use DJabberd::Log;
use DJabberd::Util qw(exml);

our $logger = DJabberd::Log->get_logger();

sub register {
    my ($self, $vhost) = @_;
    
    $self->SUPER::register($vhost);
    $logger->debug("Component ".$self." will serve domain ".$self->domain);
    return;
    
}

=head2 handles_destination($self, $to_jid, $vhost)

This class provides an overriden version of this method which responds with
a true value if and only if the domain of the JID given matches the domain
of the component itself. It is unlikely that you will need to override this.

=cut
sub handles_destination {
    my ($self, $to_jid, $vhost) = @_;
    return ($to_jid && $to_jid->domain eq $self->domain);
}

sub domain {
    return $_[0]->vhost->server_name;
}

=head2 handle_stanza($self, $vhost, $stanza)

The overriden version of this method has special behavior when dealing with
stanzas that are addressed to nodes within the domain handled by your
component. (That is, jids of the form C<user@example.com>, rather than just C<example.com>.)

When such a stanza is recieved, the C<get_node> method will be called to retrieve
an object representing that node.

If you wish to do low-level handling of all incoming stanzas, you may override this
method. As with DJabberd::Agent, overriding this method will disable all of the
higher-level handler methods unless you delegate to the overriden method.

If you would like to preserve the higher-level handler methods but not handle
nodes as separate objects, you may like to override this method to call the original
version from DJabberd::Agent as follows:

    sub handle_stanza {
        $self->DJabberd::Agent::handle_stanza(@_);
    }

With this method in place, the C<get_node> method will no longer be used and all
suitable stanzas will be passed to this instance's own handler methods regardless of
the destination JID's node name.

=cut
sub handle_stanza {
    my ($self, $vhost, $stanza) = @_;

    if ($stanza->to_jid->node) {
        my $node = $self->get_node($stanza->to_jid->node);
        unless ($node) {
            my $error = $stanza->make_error_response('404', 'cancel', 'item-not-found');
            $error->deliver($vhost);
            return;
        }
        return $node->handle_stanza($vhost, $stanza);
    }
    else {
        $self->SUPER::handle_stanza($vhost, $stanza);
    }

}

=head2 get_node($self, $nodename)

Called when this class wants to find an agent to handle a given node within this
component's domain.

Most normal implementations of this method will return an instance of a subclass of
L<DJabberd::Agent::Node|DJabberd::Agent::Node>, but really any
L<DJabberd::Agent|DJabberd::Agent> subclass will do as long as it'll accept stanzas
addressed to the nodename given.

=cut
sub get_node {
    my ($self, $nodename) = @_;

    return undef;
}

sub name {
    my ($self) = @_;
    
    return $self->domain;
}

=head2 vcard($self)

The overriden version of this method will return a vCard where the full name is set
to the domain name of the component. Subclasses may override this to do something
more fancy.

=cut
sub vcard {
    my ($self) = @_;
    
    return "<FN>".exml($self->name)."</FN>";
}

=head2 identities($self)

The overriden version of this method returns a single, generic identity which
indicates that the component is a "branch" in the Service Discovery tree.
This is included because some clients seem to get a little upset if a JID
supports disco but has no identities.

=cut
sub identities {
    my ($self) = @_;
    
    return [
        [ 'heirarchy', 'branch', $self->name ],
    ];
}

# Internal utility method.
# I don't think this is used anymore
sub send_stanza {
    my ($self, $stanza) = @_;
    
    $stanza->deliver($self->vhost);
}

1;

=head1 SEE ALSO

See also L<DJabberd::Agent>, L<DJabberd::Agent::Node>.

=head1 COPYRIGHT

Copyright 2007-2008 Martin Atkins

This module is part of the DJabberd distribution and is covered by the distribution's
overall licence.

=cut
