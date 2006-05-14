#!/usr/bin/perl
use strict;
use Test::More tests => 4;
use lib 't/lib';

require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;
    $pa->send_xml("<iq type='get' id='pa1' to='$pb'><x/></iq>");
    like($pb->recv_xml, qr/id=.pa./, "pb got pa's iq");
    $pb->send_xml("<iq type='get' id='pb1' to='$pa'><x/></iq>");
    like($pa->recv_xml, qr/id=.pb./, "pb got pa's iq");


});

