package DJabberd::Auth;
use strict;
use base 'DJabberd::Plugin';

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub register {
    my ($class, $server) = @_;
    $server->register_hook("process_stanza");
}

sub check_auth {
    my ($self, $djs, $auth_info, $cb) = @_;
    return 0;
}

1;
