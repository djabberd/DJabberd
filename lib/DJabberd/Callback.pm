package DJabberd::Callback;
use strict;
use Carp qw(croak);
our $AUTOLOAD;

sub new {
    #my ($class, $meths) = @_;
    # TODO: track where it was defined at, in debug mode?
    return bless $_[1], $_[0];
}

#sub DESTROY {
#    my $self = shift;
#    DJabberd->track_destroyed_obj($self);
#}

sub desc {
    my $self = shift;
    return $self;  # TODO: change to "Callback defined at Djabberd.pm, line 23423"
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
    my $func = $self->{$meth};
    unless ($func) {
        my $avail = join(", ", grep { $_ !~ /^_/ } keys %$self);
        croak("unknown method ($meth) called on " . $self->desc . "; available methods: $avail");
    }
    $func->($self, @_);

    # let our creator know we've fired
    if (my $postfire = $self->{_post_fire}) {
        $postfire->($meth);
    }
}

1;
