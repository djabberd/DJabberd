package DJabberd::Authen::AllowedUsers;
use strict;
use base 'DJabberd::Authen';
use Carp qw(croak);

sub new {
    my ($class, %opts) = @_;
    my $policy = delete $opts{'policy'};
    croak("policy must be 'deny' or 'accept'") unless $policy =~ /^deny|accept$/;

    my $allowed = delete $opts{'allowed'};
    my $denied  = delete $opts{'denied'};
    croak("unknown options") if %opts;

    return bless {
        policy  => $policy,
        allowed => $allowed,
        denied  => $allowed,
    }, $class;
}

sub check_cleartext {
    my ($self, $cb, %args) = @_;
    my $user = $args{'username'};

    if ($self->{'policy'} eq "deny") {
        warn "$self --- user=$user, denying, unless allowed: @{$self->{allowed}}\n";
        foreach my $allowed (@{$self->{allowed}}) {
            if (ref $allowed eq "Regexp" && $user =~ /$allowed/) {
                $cb->decline; # okay username, may continue in auth phase
                return;
            } elsif ($user eq $allowed) {
                $cb->decline; # okay username, may continue in auth phase
                return;
            }
        }
        $cb->reject;
        return;
    }

    if ($self->{'policy'} eq "accept") {
        warn "$self --- user=$user, accepting, unless denied: @{$self->{denied}}\n";
        foreach my $allowed (@{$self->{denied}}) {
            if (ref $allowed eq "Regexp" && $user =~ /$allowed/) {
                $cb->reject; # okay username, may continue in auth phase
                return;
            } elsif ($user eq $allowed) {
                $cb->reject; # okay username, may continue in auth phase
                return;
            }
        }
        $cb->decline;
        return;
    }

    $cb->reject;
}

1;
