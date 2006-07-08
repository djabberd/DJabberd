
package DJabberd::Plugin::Component;

use strict;
use base 'DJabberd::Plugin';
use warnings;
use Carp;
our $logger = DJabberd::Log->get_logger();


sub set_config_subdomain {
    my ($self, $subdomain) = @_;
    $self->{subdomain} = $subdomain;
}

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
    $logger->logdie("The Subdomain directive is required") unless $self->{subdomain};
    
    my $loaded = eval "use $self->{class}; 1;";
    $logger->logdie("Unable to load component class $self->{class}: $@") unless $loaded;
}

sub register {
    my ($self, $vhost) = @_;
    
    $self->{domain} = $self->{subdomain} . "." . $vhost->server_name;
    $vhost->register_subdomain($self->{subdomain}, __PACKAGE__);
    
    $self->{component} = $self->{class}->new($self->{domain}, $self->{component_opts});
    $logger->logdie("Failed to instantiate component $self->{class}") unless ref $self->{component};
    
    $logger->info("Attaching component $self->{domain} ($self->{class})");

    $self->{vhost} = $vhost;
    Scalar::Util::weaken($self->{vhost});
    
    $vhost->register_hook('deliver',sub {
        if ($_[2]->to_jid && $_[2]->to_jid->domain eq $self->{domain}) {
            $logger->debug("Delivering ".$_[2]->element_name." stanza to component ".$self->{domain});
            $self->{component}->handle_stanza(@_);
        }
    });
}

1;
