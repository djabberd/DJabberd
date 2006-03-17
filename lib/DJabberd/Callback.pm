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

sub already_fired {
    my $self = shift;
    return $self->{_has_been_called} ? 1 : 0;
}

sub AUTOLOAD {
    my $self = shift;
    my $meth = $AUTOLOAD;
    $meth =~ s/.+:://;

    # ignore perl-generated methods
    return unless $meth =~ /[a-z]/;

    if ($self->{_has_been_called}++) {
        warn "Callback called twice.  ignoring.\n";
        return;
    }

    if (my $pre = $self->{_pre}) {
        $pre->($self, $meth, @_) or return;
    }
    my $cb = $self->{$meth};
    unless ($cb) {
        my $avail = join(", ", grep { $_ !~ /^_/ } keys %$self);
        croak("unknown method ($meth) called on " . $self->desc . "; available methods: $avail");
    }
    $cb->($self, @_);
}

1;
