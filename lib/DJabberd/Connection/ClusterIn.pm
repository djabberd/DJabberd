package DJabberd::Connection::ClusterIn;
use strict;
use base 'DJabberd::Connection';
use DJabberd::ClusterMessage;
use DJabberd::ClusterMessage::DeliverStanza;
use fields (
            'buf',
            );
use DJabberd::Log;

sub new {
    my ($class, $sock, $server) = @_;
    my $self = Danga::Socket::new($class, $sock);

    $self->{id}      = fileno($sock);
    $self->{vhost}   = undef;  # set once we get a stream start header from them
    $self->{server}  = $server;
    $self->{buf}     = '';
    $self->{log}     = DJabberd::Log->get_logger($class);
    $self->log->debug("New clusterid connection '$self->{id}' from " . ($self->peer_ip_string || "<undef>"));
    return $self;
}

sub set_vhost {
    my ($self, $vhost) = @_;
    return 0 unless $vhost->{s2s};
    return $self->SUPER::set_vhost($vhost);
}

sub event_read {
    my $self = shift;
    my $bref = $self->read(20_000)
        or return $self->close;

    $self->{buf} .= $$bref;
    while ($self->{buf} =~ /^DJAB(....)/s) {
        my $len = unpack("N", $1);
        die "packet too big" if $len > 5 * 1024 * 1024; # arbitrary
        return unless length($self->{buf}) >= $len + 8;

        $self->{buf} =~ s/^DJAB....//s;
        my $payload = substr($self->{buf}, 0, $len, '');
        my $cmsg = eval { DJabberd::ClusterMessage->thaw(\$payload) };

        if (! $cmsg && $payload =~ /^vhost=(.+)/) {
            my $hostname = $1;
            my $vhost = $self->server->lookup_vhost($hostname)
                or $self->close;
            $self->{vhost} = $vhost;
            next;
        }

        # need a vhost past this point
        return $self->close unless $self->{vhost};

        if ($cmsg) {
            $cmsg->process($self->{vhost});
        } else {
            print "Got payload text: [$payload]\n";
        }
    }
}


1;
