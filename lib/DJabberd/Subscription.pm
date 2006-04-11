package DJabberd::Subscription;
use strict;
use Carp qw(croak);
use DJabberd::Util qw(exml);

use fields (
            'to',        # all bools
            'from',
            'pendin',
            'pendout',
            );

# The nine valid subscription states from the spec:
#                         TO  FROM  PIN  POUT
#   None                  -   -     -    -
#   None+PendOut          -   -     -    X
#   None+PendIn           -   -     X    -
#   None+PendIn+PendOut   -   -     X    X
#   To                    X   -     -    -
#   To+PendIn             X   -     X    -
#   From                  -   X     -    -
#   From+PendOut          -   X     -    X
#   Both                  X   X     -    -

# Invalid conditions:
#    TO && PendOut
#    From && PendIn


sub new {
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    return $self;
}

sub none {
    my $class = shift;
    return $class->new;
}

sub new_from_name {
    my ($class, $name) = @_;
    my $sb = {
        'none' => sub { $class->none },
        # ...
    }->{$name};
    croak "Unknown subscription state name '$name'" unless $sb;
    return $sb->();
}

sub pending_out {
    my $self = shift;
    return $self->{pendout};
}

sub sub_from {
    my $self = shift;
    return $self->{from};
}

sub sub_to {
    my $self = shift;
    return $self->{to};
}

sub set_pending_out {
    my ($self, $val) = @_;
    $val = 1 unless defined $val;
    $self->{pendout} = $val;
    return $self;
}

sub got_inbound_subscribed {
    my $self = shift;
    $self->{to}      = 1;
    $self->{pendout} = 0;
}

sub as_bitmask {
    my $self = shift;
    my $ret = 0;
    $ret = $ret | 1   if $self->{to};
    $ret = $ret | 2   if $self->{from};
    $ret = $ret | 4   if $self->{pendin};
    $ret = $ret | 8   if $self->{pendout};
    return $ret;
}

sub from_bitmask {
    my ($class, $mask) = @_;
    $mask += 0;  # force to numeric context
    my $new = $class->new;
    $new->{to}      = 1 if $mask & 1;
    $new->{from}    = 1 if $mask & 2;
    $new->{pendin}  = 1 if $mask & 4;
    $new->{pendout} = 1 if $mask & 8;
    return $new;
}

sub as_attributes {
    my $self = shift;
    my $state;
    if ($self->{to} && $self->{from}) {
        $state = "both";
    } elsif ($self->{to}) {
        $state = "to";
    } elsif ($self->{from}) {
        $state = "from";
    } else {
        $state = "none";
    }

    my $ret = "subscription='$state'";
    if ($self->{pendout}) {
        $ret .= " ask='subscribe'";
    }
    return $ret;
}

1;



