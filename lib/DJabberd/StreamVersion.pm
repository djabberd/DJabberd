# class to represent the version number in a stream attribute

package DJabberd::StreamVersion;

use constant MAJOR   => 0;
use constant MINOR   => 1;
use constant VALID   => 2;
use constant PRESENT => 3;

# returns undef on invalid version
sub new {
    my ($class, $ver) = @_;

    # {=version-format}
    my ($valid, $major, $minor) = (0, 0, 0);
    if ($ver =~ /^(\d+)\.(\d+)$/) {
        $valid = 1;
        ($major, $minor) = ($1, $2);
        # {=leading-zeros-ignored}
        $major =~ s/^0+//;
        $minor =~ s/^0+//;
    }

    return bless [
                  int($major || 0),
                  int($minor || 0),
                  $valid,
                  ($ver ne "" ? 1 : 0),
                  ], $class;
}

sub none {
    my $class = shift;
    return bless [ 0, 0, 1, 0 ], $class;
}

# returns min of two given objects
sub min {
    return (sort { $a->cmp($b) } @_)[0];
}

sub valid {
    my $self = shift;
    return $self->[VALID];
}

sub supports_features {
    my $self = shift;
    return $self->at_least("1.0");
}

sub at_least {
    my ($self, $other) = @_;
    my $cmp = $self->cmp($other);
    return $cmp >= 0;
}

# {=numeric-version-compare}
sub cmp {
    my ($self, $other) = @_;
    $other = DJabberd::StreamVersion->new($other) unless ref $other;
    return
        ($self->[MAJOR] <=> $other->[MAJOR]) ||
        ($self->[MINOR] <=> $other->[MINOR]);
}

sub as_string {
    my $self = shift;
    return "$self->[MAJOR].$self->[MINOR]";
}

# returns "version='1.0'" or empty string when version is 0.0;
# {=no-response-version-on-zero-ver}
sub as_attr_string {
    my $self = shift;
    return "" unless $self->[MAJOR] || $self->[MINOR];
    return "version='" . $self->as_string . "'";
}

1;
