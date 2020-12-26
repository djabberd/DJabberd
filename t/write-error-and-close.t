#!/usr/bin/perl
use strict;
use Test::More tests => 5;
use lib 't/lib';

# enable ability to do djabberd:test IQ to break writes.
$ENV{DJABBERD_TEST_COMMANDS} = 1;

require 'djabberd-test.pl';

two_parties_one_server(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    # now pa/pb send presence to become available resources
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");

    # add ourself to our roster, so when we die, the server will send
    # us our own disconnect info, causing infinite recursion if server
    # isn't careful.
    $pa->subscribe_successfully($pa);

    # this will switch our writer in error-and-close mode.
    $pa->send_xml("<iq type='set' id='foo'><query xmlns='djabberd:test'>write error</query></iq>");
    # this could (cause the server to blow up)
    ok(!$pa->recv_xml(1.5), "didn't get an answer");

    # PB to self (see if server still alive)
    $pb->send_xml("<message type='chat' to='$pb'>Hello myself!</message>");
    like($pb->recv_xml, qr/Hello myself/, "pb got own message");


});

