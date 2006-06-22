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

sub freeze {
    my $self = shift;
    
    return Storable::nfreeze( $self );
}

sub thaw {
    my $class = shift;
    my $data = shift;
   
    return Storable::thaw( $data );
}
