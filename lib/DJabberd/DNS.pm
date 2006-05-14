package DJabberd::DNS;
use strict;
use base 'Danga::Socket';
use fields (
            'hostname',
            'callback',
            'srv',
            'port',
            );
use Carp qw(croak);

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

use Net::DNS;
my $resolver    = Net::DNS::Resolver->new;

sub srv {
    my ($class, %opts) = @_;

    foreach (qw(callback domain service)) {
        croak("No '$_' field") unless $opts{$_};
    }

    my $hostname = delete $opts{'domain'};
    my $callback = delete $opts{'callback'};
    my $service  = delete $opts{'service'};
    my $port     = delete $opts{'port'};
    croak "unknown opts" if %opts;

    # default port for s2s
    $port ||= 5269 if $service eq "_xmpp-server._tcp";
    croak("No specified 'port'") unless $port;

    # testing support
    if ($service eq "_xmpp-server._tcp") {
        my $endpt = DJabberd->fake_s2s_peer($hostname);
        if ($endpt) {
            $callback->($endpt);
            return;
        }
    }

    my $pkt = Net::DNS::Packet->new("$service.$hostname", "SRV", "IN");

    $logger->debug("pkt = $pkt");
    my $sock = $resolver->bgsend($pkt);
    $logger->debug("sock = $sock");
    my $self = $class->SUPER::new($sock);

    $self->{hostname} = $hostname;
    $self->{callback} = $callback;
    $self->{srv}      = $service;
    $self->{port}     = $port;

    # TODO: set a timer to fire with lookup error in, say, 5 seconds
    # or whatever caller wants
    $self->watch_read(1);

}

sub new {
    my ($class, %opts) = @_;

    foreach (qw(hostname callback port)) {
        croak("No '$_' field") unless $opts{$_};
    }

    my $hostname = delete $opts{'hostname'};
    my $callback = delete $opts{'callback'};
    my $port     = delete $opts{'port'};
    croak "unknown opts" if %opts;

    my $sock = $resolver->bgsend($hostname);
    my $self = $class->SUPER::new($sock);

    $self->{hostname} = $hostname;
    $self->{callback} = $callback;
    $self->{port}     = $port;

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
            if ($ans->isa('Net::DNS::RR::CNAME')) {
                $self->close;
                DJabberd::DNS->new(hostname => $ans->cname,
                                   port     => $self->{port},
                                   callback => $cb);
            }
            else {
                $cb->(DJabberd::IPEndPoint->new($ans->address, $self->{port}));
            }
            $self->close;
            1;
        };
        if ($@) {
            die "ERROR in DNS world: [$@]\n";
        }
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
        # no result, fallback to an A lookup
        $self->close;
        DJabberd::DNS->new(hostname => $self->{hostname},
                           port     => $self->{port},
                           callback => $cb);
        return;
    }

    # FIXME:  we only do the first target now.  should do a chain.
    DJabberd::DNS->new(hostname => $targets[0]->target,
                       port     => $targets[0]->port,
                       callback => $cb);
    $self->close;
}

package DJabberd::IPEndPoint;
sub new {
    my ($class, $addr, $port) = @_;
    return bless { addr => $addr, port => $port };
}

sub addr { $_[0]{addr} }
sub port { $_[0]{port} }

1;
