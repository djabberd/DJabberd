package DJabberd::DNS;
use strict;
use base 'Danga::Socket';
use fields (
            'hostname',
            'callback',
            );

use Net::DNS;
my $resolver    = Net::DNS::Resolver->new;

sub new {
    my ($class, %opts) = @_;

    my $hostname = delete $opts{'hostname'};
    my $callback = delete $opts{'callback'};

    my $sock = $resolver->bgsend($hostname);
    my $self = $class->SUPER::new($sock);

    $self->{hostname} = $hostname;
    $self->{callback} = $callback;

    # TODO: set a timer to fire with lookup error in, say, 5 seconds
    # or whatever caller wants

    $self->watch_read(1);
}

# TODO: verify response is for correct thing?  or maybe Net::DNS does that?
# TODO: lots of other stuff.
sub event_read {
    my $self = shift;

    my $sock = $self->{sock};
    my $cb   = $self->{callback};

    my $packet = $resolver->bgread($sock);

    my @ans = $packet->answer;

    for my $ans (@ans) {
        my $rv = eval {
            $cb->($ans->address);
            $self->close;
            1;
        };
        return if $rv;
    }

    # no result
    $self->close;
    $cb->(undef);
}

1;
