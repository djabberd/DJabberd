package DJabberd::Cluster;
use strict;
use base 'DJabberd::Plugin';
use DJabberd::Queue::ClusterOut;

sub register {
    my ($self, $vhost) = @_;
    $self->{vhost} = $vhost;

    $vhost->register_hook("ClusterDeliverMessage", sub {
        my (undef, $cb, $barejid, $message) = @_;
        $self->deliver_cluster_message($barejid, $message, $cb);
    });
}

# protocol:
#    4 bytes  -- MAGIC
#    length, barejid
#    length, handler func  ???
#    length, opaque data (if a ref, we storable/thaw it)

# don't subclass.
sub deliver_star {
    my ($self, $barejid, $endpts_list, $cb) = @_;
    # $cb can ->done, ->error
}

# subclass if you're Spread or have a fancy message bus.
sub deliver_message {
    my ($self, $barejid, $message, $cb) = @_;
    if ($self->can('find_barejid_locations')) {
        my @endpts = $self->find_barejid_locations($barejid);
        $self->deliver_star($barejid, \@endpts, $cb);
    }
    $cb->error;
}

# subclass if you're lazy and want to use a star delivery topology
#sub find_barejid_locations {
#}

1;
