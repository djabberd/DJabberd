package DJabberd::Authen::InMemoryOnly;
use strict;
use base 'DJabberd::Authen';
use Carp qw(croak);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new;
    $self->{_users} = {};  # username -> $password
    return $self;
}

sub can_register_jids { 1 }
sub can_unregister_jids { 1 }
sub can_retrieve_cleartext { 1 }

sub unregister_jid {
    my ($self, $cb, %args) = @_;
    my $user = $args{'username'};
    if (delete $self->{_users}{$user}) {
        $cb->deleted;
    } else {
        $cb->notfound;
    }
}

sub register_jid {
    my ($self, $cb, %args) = @_;
    my $user = $args{'username'};
    my $pass = $args{'password'};

    if (defined $self->{_users}{$user}) {
        $cb->conflict;
    }

    $self->{_users}{$user} = $pass;
    $cb->saved;
}

sub check_cleartext {
    my ($self, $cb, %args) = @_;
    my $user = $args{'username'};

    my $pass = $args{'password'};
    unless (defined $self->{_users}{$user}) {
        return $cb->reject;
    }

    my $goodpass = $self->{_users}{$user};
    unless ($pass eq $goodpass) {
        return $cb->reject;
    }

    $cb->decline;
}

sub get_password {
    my ($self, $cb, %args) = @_;
    my $user = $args{'username'};
    if (my $pass = $self->{_users}{$user}) {
        $cb->set($pass);
        return;
    }
    $cb->decline;
}

1;
