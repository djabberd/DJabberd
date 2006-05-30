package DJabberd::Authen::AllowedUsers;
use strict;
use base 'DJabberd::Authen';
use Carp qw(croak);

sub set_config_policy {
    my ($self, $policy) = @_;
    $policy = lc $policy;
    croak("Policy must be 'deny' or 'accept'") unless $policy =~ /^deny|accept$/;
    $self->{policy} = $policy;
}

sub set_config_allowedusers {
    my ($self, $val) = @_;
    $self->{allowed} = ref $val ? $val : [ split(/\s+/, $val) ];
}

sub set_config_deniedusers {
    my ($self, $val) = @_;
    $self->{denied} = ref $val ? $val : [ split(/\s+/, $val) ];
}

sub finalize {
    my $self = shift;
    # just for error checking:
    $self->set_config_policy($self->{policy});
    $self->{allowed} ||= [];
    $self->{denied}  ||= [];
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
sub check_jid {
    my $self = shift;

    warn "check_jid";
}

1;
