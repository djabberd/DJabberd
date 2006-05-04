package DJabberd::Delivery;
use strict;
use warnings;
use base 'DJabberd::Plugin';

use Scalar::Util;

sub new {
    my ($class) = @_;
    return bless {
        'vhost' => undef,
    }, $class;
}

sub register {
    my ($self, $vhost) = @_;
    $self->set_vhost($vhost);
    $vhost->register_hook("deliver", sub { $self->deliver(@_) });
}

sub set_vhost {
    my ($self, $vhost) = @_;
    Carp::croak("Not a vhost: '$vhost'") unless UNIVERSAL::isa($vhost, "DJabberd::VHost");
    $self->{vhost} = $vhost;
    Scalar::Util::weaken($self->{vhost});
}

1;
