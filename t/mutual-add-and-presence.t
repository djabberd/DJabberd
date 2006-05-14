#!/usr/bin/perl
use strict;
use Test::More tests => 26;
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

    $pa->send_xml(qq{<presence to='$pb' type='subscribe' />});

    my $xml = $pa->recv_xml;
    like($xml, qr/\bask=.subscribe\b/, "subscribe is pending");

    $xml = $pb->recv_xml_obj;
    is($xml->attr("{}to"), $pb->as_string, "to pb");
    is($xml->attr("{}from"), $pa->as_string, "from a");
    is($xml->attr("{}type"), "subscribe", "type subscribe");

    $pb->send_xml(qq{<presence to='$pa' type='subscribed' />});
    $xml = $pb->recv_xml;
    like($xml, qr/\bsubscription=.from\b/, "subscription from item");

    # now PA gets a roster push and the subscribed packet
    @xml = ($pa->recv_xml, $pa->recv_xml);
    # flip them if presence came first.
    @xml = ($xml[1], $xml[0]) if $xml[0] =~ /\btype=.subscribed\b/;
    # so order is 0: roster push, 1: presence subscribed
    like($xml[0], qr/\bsubscription=.to\b/, "has subscription to");
    like($xml[1], qr/\btype=.subscribed\b/, "got subscribed back");
    like($xml[1], qr/\bfrom=.$pb\b/, "got subscribed back from $pb");

    # now PA is subscribed to PB.  so let's make PB be present.
    $pb->send_xml(qq{<presence/>});

    # let's pretend pa gets confused and asks again, pb's server should
    # reply immediately with the answer
    $xml = $pa->recv_xml;
    like($xml, qr/<presence.+\bfrom=.$pb/, "got presence of pb");

});
