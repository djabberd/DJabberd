package DJabberd::Stanza::StreamFeatures;
use strict;
use warnings;
use base qw(DJabberd::Stanza);

sub on_recv_from_server {
    my ($self, $conn) = @_;
    $conn->set_rcvd_features($self);
}

sub acceptable_from_server { 1 }

# TODO: add methods like ->supports_tls, ->supports_sasl, etc...

1;
