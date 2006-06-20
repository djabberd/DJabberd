#!/usr/bin/perl
use strict;
use Test::More tests => 4;
use lib 't/lib';

require 'djabberd-test.pl';

# with a to in outgoing verify stream,
$DJabberd::_T_NO_TO_IN_DIALBACKVERIFY_STREAM = 0;
test();

# without to in outgoing verify stream,
$DJabberd::_T_NO_TO_IN_DIALBACKVERIFY_STREAM = 1;
test();

sub test {
    two_parties_s2s(sub {
        my ($pa, $pb) = @_;
        $pa->login;
        $pb->login;
        $pa->send_xml("<presence/>");
        $pb->send_xml("<presence/>");

        # PA to PB
        $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
        like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

        # PB to PA
        $pb->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
        like($pa->recv_xml, qr/Hello back/, "pa got pb's message");

    });
}

