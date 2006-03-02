package DJabberd::Callback;
use strict;
use Carp qw(croak);
our $AUTOLOAD;

sub new {
    my ($class, %meth) = @_;
    # ... caller() ... store in $self
    return bless \%meth, $class;
}

sub desc {
    my $self = shift;
    return $self;  # FIXME: change to "Callback defined at Djabberd.pm, line 23423"
}

sub AUTOLOAD {
    my $self = shift;
    my $meth = $AUTOLOAD;
    $meth =~ s/.+:://;

    # ignore perl-generated methods
    return unless $meth =~ /[a-z]/;

    if (my $pre = $self->{_pre}) {
        $pre->($self, $meth, @_) or return;
    }
    my $cb = $self->{$meth} or
        croak("unknown method ($meth) called on " . $self->desc);
    $cb->($self, @_);
}

1;
