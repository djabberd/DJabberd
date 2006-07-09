
=head1 NAME

DJabberd::Delivery::Component - Delivery via a Component

=head1 SYNOPSIS

<VHost example.mydomain.com>

  [...]

  <Plugin DJabberd::Delivery::Component>
    Class DJabberd::Component::Example
    Greeting I'm an example component bound to a VHost!
  </Plugin>

  [...]

</VHost>

This delivery plugin instantiates a component and delivers all
locally-addressed messages to that component. Any messages to other
domains are declined, so these can be handed on to another delivery
plugin if desired.

TODO: Write more docs

=cut

package DJabberd::Delivery::Component;

use strict;
use warnings;
use base 'DJabberd::Delivery';
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub set_config_class {
    my ($self, $class) = @_;
    $logger->logdie("Invalid classname $class") if $class =~ /[^\w:]/;
    $self->{class} = $class;
}

# Pass any unrecognised configuration parameters on to the component itself
sub set_config__option {
    my ($self, $key, $val) = @_;
    $self->{component_opts} ||= {};
    $self->{component_opts}{$key} = $val;
}

sub finalize {
    my ($self) = @_;

    $logger->logdie("The Class directive is required") unless $self->{class};

    my $loaded = eval "use $self->{class}; 1;";
    $logger->logdie("Unable to load component class $self->{class}: $@") unless $loaded;

    $logger->debug("Component class $self->{class} bound to vhost");

}

sub register {
    my ($self, $vhost) = @_;
    
    $self->SUPER::register($vhost);
    
    $self->{component} = $self->{class}->new($vhost->server_name, $self->{component_opts});
    $logger->logdie("Failed to instantiate component $self->{class}") unless ref $self->{component};
}

sub deliver {
    my ($self, $vhost, $cb, $stanza) = @_;

    $logger->debug("Got a nice stanza: ".$stanza->as_summary);

    if ($stanza->to_jid && $vhost->handles_domain($stanza->to_jid->domain)) {
        $logger->debug("Delivering ".$stanza->element_name." stanza via component ".$self->{class});
        $self->{component}->handle_stanza($vhost, $cb, $stanza);
    }
    else {
        $logger->debug("This stanza is not for ".$vhost->server_name);
        $cb->decline;
    }

}

1;
