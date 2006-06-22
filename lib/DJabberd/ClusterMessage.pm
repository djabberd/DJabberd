package DJabberd::ClusterMessage;
use strict;
use warnings;

use Storable ();
use fields ();

sub new {
    my $self = shift;
    $self = fields::new($self) unless ref $self;

    return $self;
}

sub thaw {
    my ($class, $dataref) = @_;
    return Storable::thaw($$dataref);
}

sub as_packet {
    my $self = shift;
    my $freeze = Storable::nfreeze($self);
    return "DJAB" . pack("N", length $freeze) . $freeze;
}

sub process {
    my ($self, $vhost) = @_;
    print "processing $self w/ vhost = $vhost\n";
}

1;
