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



