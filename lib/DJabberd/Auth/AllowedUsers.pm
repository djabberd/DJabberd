package DJabberd::Auth::AllowedUsers;
use strict;
use base 'DJabberd::Auth';

sub new {
    my ($class, %opts) = @_;
    my $policy = delete $opts{'policy'};
    # FIXME: croak if not accept/deny
    my $allowed = delete $opts{'allowed'};
    return bless {
        policy  => $policy,
        allowed => $allowed,
    }, $class;
}

sub check_auth {
    my ($self, $conn, $auth_info, $cb) = @_;
    my $user = $auth_info->{'username'};

    warn "$self --- user=$user, allowed: @{$self->{allowed}}\n";

    if ($self->{'policy'} eq "deny") {
        if (grep { $user eq $_ } @{$self->{allowed}}) {
            $cb->decline;  # okay username, may continue in auth phase
        } else {
            $cb->reject;
        }
        return;
    }

    # TODO: policy accept

    return 0;
}

1;
