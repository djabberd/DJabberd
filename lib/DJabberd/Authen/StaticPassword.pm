package DJabberd::Authen::StaticPassword;
use strict;
use base 'DJabberd::Authen';

sub set_config_password {
    my ($self, $pass) = @_;
    $self->{password} = $pass;
}

sub can_retrieve_cleartext { 1 }

sub get_password {
    my ($self, $cb, %args) = @_;
    $cb->set($self->{password});
}

sub check_cleartext {
    my ($self, $cb, %args) = @_;
    if ($args{password} eq $self->{password}) {
        $cb->accept;
        return;
    }
    $cb->reject;
}

1;
