#!/usr/bin/perl
use strict;
use Test::More tests => 8;
use lib 't/lib';
require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    $pa->send_xml(qq{<iq type='set' id='set1'>
  <query xmlns='jabber:iq:roster'>
    <item
        jid='$pb'
        name='MrB'>
      <group>Friends</group>
    </item>
  </query>
</iq>});

    my @xml = sort { length($a) <=> length($b) } ($pa->recv_xml, $pa->recv_xml);
    like($xml[0], qr/type=.result\b/, "got IQ result");
    like($xml[1], qr/MrB.+Friends/s, "got roster push back");
    like($xml[1], qr/\bsubscription=.none\b/, "no subscription either way");
    unlike($xml[1], qr/\bask\b/, "no pending");

    #$pa->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
    #like($pa->recv_xml, qr/Hello back/, "pa got pb's message");

});
