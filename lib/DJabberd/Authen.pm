package DJabberd::Authen;
use strict;
use base 'DJabberd::Plugin';

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

    $server->register_hook("CheckJID", sub {
        my (undef, $cb, %args) = @_;
        # args contain: username and conn
        $self->check_jid($cb, %args);

    });

    if ($self->can_register_jids) {
        $server->register_hook("RegisterJID", sub {
            my (undef, $cb, %args) = @_;
            # args containing:  username, password
            # cb can:
            #   conflict
            #   error
            #   saved
            $self->register_jid($cb, %args);
        });
    }

}

sub can_register_jids {
    0;
}

sub can_retrieve_cleartext {
    0;
}


sub check_jid {
    my ($self, $cb, %args) = @_;
    return 0;
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
