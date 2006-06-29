package DJabberd::Authen;
use strict;
use base 'DJabberd::Plugin';

sub register {
    my ($self, $vhost) = @_;

#    my $which;
#    if (($which = $self->can('foo')) && $which != &base_class_one) {
#    }

    if ($self->can_retrieve_cleartext) {
        $vhost->register_hook("GetPassword", sub {
            my (undef, $cb, %args) = @_;
            # args as 'username' and 'conn';
            # cb can ->set or ->decline
            $self->get_password($cb, %args);
        });
    }

    if ($self->can_check_digest) {
        $vhost->register_hook("CheckDigest", sub {
            my (undef, $cb, %args) = @_;
            # args as 'username', 'conn', 'digest'
            # cb can ->accept or ->reject
            $self->check_digest($cb, %args);
        });
    }

    $vhost->register_hook("CheckCleartext", sub {
        my (undef, $cb, %args) = @_;
        # args containing:  username, conn, password
        $self->check_cleartext($cb, %args);
    });

    $vhost->register_hook("CheckJID", sub {
        my (undef, $cb, %args) = @_;
        # args contain: username and conn
        $self->check_jid($cb, %args);

    });

    if ($self->can_register_jids) {
        $vhost->register_hook("RegisterJID", sub {
            my (undef, $cb, %args) = @_;
            # args containing:  username, password
            # cb can:
            #   conflict
            #   error
            #   saved
            $self->register_jid($cb, %args);
        });
    }

    if ($self->can_unregister_jids) {
        $vhost->register_hook("UnregisterJID", sub {
            my (undef, $cb, %args) = @_;
            # args containing:  username
            # cb can:
            #   conflict
            #   error
            #   saved
            $self->unregister_jid($cb, %args);
        });
    }

}

sub can_register_jids {
    0;
}

sub can_unregister_jids {
    0;
}

sub can_retrieve_cleartext {
    0;
}

sub can_check_digest {
    0;
}

sub check_jid {
    my ($self, $cb, %args) = @_;
    return 0;
}

sub unregister_jid {
    my ($self, $cb, %args) = @_;
    return 0;
}

sub check_cleartext {
    my ($self, $cb, %args) = @_;
    $cb->reject;
}

sub check_digest {
    my ($self, $cb, %args) = @_;
    $cb->reject;
}


1;
