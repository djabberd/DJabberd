#!/usr/bin/perl
use strict;
use Test::More tests => 4;
use lib 't/lib';

require 'djabberd-test.pl';

use Authen::SASL 'Perl';

my $login_and_be = sub {
    my ($pa, $pb, $sasl) = @_;

    $pa->sasl_login($sasl);
    $pb->login;
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");

#    do {
#        select(undef,undef,undef,0.05);
#    } until ($content)

    $pa->send_xml("<iq type='get' id='pa1' to='$pb'><x/></iq>");
    like($pb->recv_xml, qr/id=.pa./, "pb got pa's iq");
    $pb->send_xml("<iq type='get' id='pb1' to='$pa'><x/></iq>");
    like($pa->recv_xml, qr/id=.pb./, "pb got pa's iq");
};

for my $mechanism (qw/PLAIN LOGIN DIGEST-MD5/) {
    two_parties(sub {
        my ($pa, $pb) = @_;

        my $sasl = Authen::SASL->new(
            mechanism => $mechanism,
            callback  => {
                pass => sub { $pa->password },
                user => sub { $pa->{name}   },
            },
        );

        $login_and_be->($pa, $pb, $sasl);
    });
}
