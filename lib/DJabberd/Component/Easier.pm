
# An abstract base class providing a higher-level API for
# component implementation.
# Subclasses can override different functions to override
# behavior at a variety of levels.

package DJabberd::Component::Easier;
use base qw(DJabberd::Agent);
use DJabberd::Component::Easier::Node;
use strict;
use warnings;
use DJabberd::Util qw(exml);
use DJabberd::JID;


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

sub get_node {
    my ($self, $nodename) = @_;

    # FIXME: Make this return undef by default, to signify that no nodes exist
    return DJabberd::Component::Easier::Node->fetch($nodename, $self);
}

sub name {
    my ($self) = @_;
    
    return $self->domain;
}

sub vcard {
    my ($self) = @_;
    
    return "<FN>".exml($self->name)."</FN>";
}

sub identities {
    my ($self) = @_;
    
    # Use a generic identity by default because some clients
    # get upset if a JID has no identities.
    # Subclasses really should specialize this.
    return [
        [ 'heirarchy', 'branch', $self->name ],
    ];
}

1;
