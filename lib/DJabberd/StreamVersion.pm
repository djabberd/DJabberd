# class to represent the version number in a stream attribute

package DJabberd::StreamVersion;

# returns undef on invalid version
sub new {
    my ($class, $ver) = @_;

    my $valid = 0;
    $valid = 1 if $ver =~ /^(\d+)\.(\d+)$/;

    return bless {
        major => $1 || 0,
        minor => $2 || 0,
        valid => $valid,
        present => ($ver ne "" ? 1 : 0),
    };
}

sub none {
    my $class = shift;
    return bless {
        major => 0,
        minor => 0,
        valid => 1,
        present => 0,
    }, $class;
}

# returns min of two given objects
sub min {
    return (sort { $a->cmp($b) } @_)[0];
}

sub valid {
    my $self = shift;
    return $self->{valid};
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
        ($self->{major} <=> $other->{major}) ||
        ($self->{minor} <=> $other->{minor});
}

sub as_string {
    my $self = shift;
    return "$self->{major}.$self->{minor}";
}

# returns "version='1.0'" or empty string when version is 0.0;
# {=no-response-version-on-zero-ver}
sub as_attr_string {
    my $self = shift;
    return "" unless $self->{major} || $self->{minor};
    return "version='" . $self->as_string . "'";
}

1;
