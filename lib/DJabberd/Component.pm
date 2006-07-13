
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

use strict;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub new {
    my ($class, $domain, $opts) = @_;

    my $self = bless {
        _component_domain => $domain,
    }, $class;
    
    $self->initialize($opts);
    
    return $self;
}

sub initialize { }

sub domain {
    return $_[1] ? $_[0]->{_component_domain} = $_[1] : $_[0]->{_component_domain};
}

sub handle_stanza {
    my ($self, $vhost, $stanza) = @_;

    $logger->warn("handle_stanza not implemented for $self");
}

1;
