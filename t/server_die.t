#!/usr/bin/perl
use strict;
use Test::More tests => 4;
use lib 't/lib';
BEGIN { require 'djabberd-test.pl' }

two_parties_s2s(sub {
    my ($pa, $pb) = @_;

    $pa->login;
    $pb->login;
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");

    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");
    $pb->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
    like($pa->recv_xml, qr/Hello back/, "pa got pb's message");

    my $server = $pa->server;
    $server->kill;
    $server->start;
    $pa->login;
    $pa->send_xml("<presence/>");

    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");
    $pb->send_xml("<message type='chat' to='$pa'>Alive again?</message>");
    like($pa->recv_xml, qr/Alive again/, "pa got pb's message");

});

