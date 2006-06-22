package DJabberd::Connection::ClusterIn;
use strict;
use base 'DJabberd::Connection';
use fields (
            'buf',
            );
use DJabberd::Log;

sub new {
    my ($class, $sock, $server) = @_;
    my $self = Danga::Socket::new($class, $sock);

    $self->{vhost}   = undef;  # set once we get a stream start header from them
    $self->{server}  = $server;
    $self->{buf}     = '';
    $self->{log}     = DJabberd::Log->get_logger($class);
    $self->log->debug("New clusterid connection from " . ($self->peer_ip_string || "<undef>"));
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


}


1;
