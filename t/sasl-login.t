#!/usr/bin/perl
use strict;
use Test::More tests => 4;
use lib 't/lib';

require 'djabberd-test.pl';

use Authen::SASL 'Perl';

## mixed login
two_parties(sub {
    my ($pa, $pb) = @_;

    my $sasl = Authen::SASL->new(
        mechanism => 'PLAIN',
        callback  => {
            pass => sub { $pa->password },
            user => sub { $pa->{name} },
        },
    );

    $pa->sasl_login($sasl);
    $pb->login;
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");
    select(undef,undef,undef,0.25);

    $pa->send_xml("<iq type='get' id='pa1' to='$pb'><x/></iq>");
    $DB::single=1;
    like($pb->recv_xml, qr/id=.pa./, "pb got pa's iq");
    $pb->send_xml("<iq type='get' id='pb1' to='$pa'><x/></iq>");
    like($pa->recv_xml, qr/id=.pb./, "pb got pa's iq");

});

