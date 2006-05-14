#!/usr/bin/perl
use strict;
use Test::More tests => 4;
use lib 't/lib';

require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;
    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");
    $pa->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
    like($pa->recv_xml, qr/Hello back/, "pa got pb's message");

});

