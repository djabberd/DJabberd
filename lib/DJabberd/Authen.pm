package DJabberd::Auth;
use strict;
use base 'DJabberd::Plugin';

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub register {
    my ($self, $server) = @_;
    $server->register_hook("Auth", sub {
        warn "Auth.pm hook called with @_\n";
        my ($conn, $cb, $auth_info) = @_;

        my $rv = $self->check_auth($conn, $auth_info, $cb);
        warn "  got rv = $rv\n";
        if (defined $rv && ! $cb->already_fired) {
            $cb->accept if $rv;
            $cb->reject if ! $rv;
        }

    });

    if ($self->can_retrieve_cleartext) {
        $server->register_hook("GetPassword", sub {
            #...
        });
    }
}

sub can_retrieve_cleartext {
    0;
}

sub check_auth {
    my ($self, $djs, $auth_info, $cb) = @_;
    return 0;
}

1;
