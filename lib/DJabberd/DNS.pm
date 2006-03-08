package DJabberd::DNS;
use strict;
use base 'Danga::Socket';
use fields (
            'hostname',
            'callback',
            'srv',
            );

use Net::DNS;
my $resolver    = Net::DNS::Resolver->new;

sub srv {
    my ($class, %opts) = @_;

    my $hostname = delete $opts{'domain'};
    my $callback = delete $opts{'callback'};
    my $service  = delete $opts{'service'};

    my $pkt = Net::DNS::Packet->new("$service.$hostname", "SRV", "IN");

    warn "pkt = $pkt\n";
    my $sock = $resolver->bgsend($pkt);
    warn "sock = $sock\n";
    my $self = $class->SUPER::new($sock);

    $self->{hostname} = $hostname;
    $self->{callback} = $callback;
    $self->{srv}      = $service;

    # TODO: set a timer to fire with lookup error in, say, 5 seconds
    # or whatever caller wants

    $self->watch_read(1);

}

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

    if ($self->{srv}) {
        return $self->event_read_srv;
    } else {
        return $self->event_read_a;
    }
}

sub event_read_a {
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

sub event_read_srv {
    my $self = shift;

    my $sock = $self->{sock};
    my $cb   = $self->{callback};

    my $packet = $resolver->bgread($sock);
    my @ans = $packet->answer;

    # FIXME: is this right?  right order and direction?
    my @targets = sort {
        $a->priority <=> $b->priority ||
        $a->weight   <=> $b->weight
    } grep { ref $_ eq "Net::DNS::RR::SRV"} @ans;

    unless (@targets) {
        # no result
        $self->close;
        $cb->(undef);
    }

    # FIXME:  we only do the first target now.  should do a chain.
    # FIXME:  we lose the port information from the srv request with this.  need to change
    #         the interface.  for now assume port 5269 in the caller, which is wrong.
    DJabberd::DNS->new(hostname => $targets[0]->target,
                       callback => $cb);
    $self->close;
}

1;
