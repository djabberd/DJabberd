package DJabberd::Auth;
use strict;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub check_auth {
    my ($self, $djs, $auth_info, $cb) = @_;
    return 0;
}

1;
