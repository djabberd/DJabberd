#!/usr/bin/perl
use strict;
use Test::More tests => 8;
use lib 't/lib';

require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    # pb isn't yet an available resource, so should not get the message
    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    unlike($pb->recv_xml(1.5), qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb getting message as unavailable resource");

    # now pa/pb send presence to become available resources
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");

    # PA to PB
    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

    # PB to PA
    $pb->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
    like($pa->recv_xml, qr/Hello back/, "pa got pb's message");

    # PA to self
    $pa->send_xml("<message type='chat' to='$pa'>Hello myself!</message>");
    like($pa->recv_xml, qr/Hello myself/, "pa got own message");

});

