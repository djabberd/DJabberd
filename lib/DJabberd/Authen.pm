package DJabberd::Authen;
use strict;
use base 'DJabberd::Plugin';

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub register {
    my ($self, $server) = @_;
    if ($self->can_retrieve_cleartext) {
        $server->register_hook("GetPassword", sub {
            my (undef, $cb, %args) = @_;
            # args as 'username' and 'conn';
            # cb can ->set or ->decline
            $self->get_password($cb, %args);
        });
    }

    $server->register_hook("CheckCleartext", sub {
        my ($conn, $cb, %args) = @_;
        # args containing:  username, conn, password
        $self->check_cleartext($cb, %args);
    });
}

sub can_retrieve_cleartext {
    0;
}

sub check_cleartext {
    my ($self, $cb, %args) = @_;
    $cb->reject;
}

sub check_auth {
    my ($self, $djs, $auth_info, $cb) = @_;
    return 0;
}

1;
