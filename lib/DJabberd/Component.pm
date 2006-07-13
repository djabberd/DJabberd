
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

use base 'DJabberd::Delivery';
use strict;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub register {
    my ($self, $vhost) = @_;
    
    $self->{component_vhost} = $vhost;
    
    $logger->debug("Component ".$self." will serve domain ".$self->domain);
    
    return $self->SUPER::register($vhost);
}

sub deliver {
    my ($self, $vhost, $cb, $stanza) = @_;

    $logger->debug("Got a nice stanza: ".$stanza->as_summary);

    # FIXME: Maybe this should require an exact match on the vhost domain, rather than handles_domain?
    if ($stanza->to_jid && $vhost->handles_domain($stanza->to_jid->domain)) {
        $logger->debug("Delivering ".$stanza->element_name." stanza via component ".$self->{class});
        $self->handle_stanza($vhost, $stanza);
        $cb->delivered;
    }
    else {
        $logger->debug("This stanza is not for ".$vhost->server_name);
        $cb->decline;
    }
}

sub domain {
    return $_[0]->{component_vhost}->server_name;
}

sub handle_stanza {
    my ($self, $vhost, $stanza) = @_;

    $logger->warn("handle_stanza not implemented for $self");
}

1;
