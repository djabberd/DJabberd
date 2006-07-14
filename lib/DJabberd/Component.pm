
=head1 NAME

DJabberd::Component - Abstract class representing a component in DJabberd

=head1 SYNOPSIS

    package MyPackage::DJabberd::MyComponent;
    use base DJabberd::Component;
    
    sub initialize {
        my ($self, $opts) = @_;
        
        # ... perform initialization
    }
    
    sub handle_stanza {
        my ($self, $vhost, $cb, $stanza) = @_;
        
        # ... handle the given stanza
    }

This class provides a parent class for all DJabberd components. Components
that inherit from this class can then be used directly by the server via the
DJabberd::Plugin::Component plugin, or used directly by other classes.

See DJabberd::Component::Example for an example component implementation.

TODO: Write more docs

=cut

package DJabberd::Component;

use base 'DJabberd::Agent';
use strict;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub register {
    my ($self, $vhost) = @_;
    
    $self->{component_vhost} = $vhost;
    
    $logger->debug("Component ".$self." will serve domain ".$self->domain);
    
    return $self->SUPER::register($vhost);
}

sub handles_destination {
    my ($self, $to_jid, $vhost) = @_;
    return ($to_jid && $to_jid->domain eq $self->domain);
}

sub domain {
    return $_[0]->{component_vhost}->server_name;
}


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

    return undef;
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
