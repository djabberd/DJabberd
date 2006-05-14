#!/usr/bin/perl
use strict;
use Test::More tests => 22;
use lib 't/lib';
require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;

    $pb->login;
    $pb->send_xml(qq{<presence><status>InitPres</status></presence>});

    $pa->send_xml(qq{<iq type='set' id='set1'>
  <query xmlns='jabber:iq:roster'>
    <item
        jid='$pb'
        name='MrB'>
      <group>Friends</group>
    </item>
  </query>
</iq>});


    test_responses($pa,
                   "IQ result" => sub {
                       my ($xo, $xml) = @_;
                       $xml =~ /type=.result/;
                   },
                   "roster push" => sub {
                       my ($xo, $xml) = @_;
                       $xml =~ /MrB.+Friends/s &&
                           $xml =~ /\bsubscription=.none\b/ &&
                           $xml !~ /\bask\b/;
                   });

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
    test_responses($pa,
                   "roster push" => sub {
                       my ($xo, $xml) = @_;
                       $xml =~ /\bsubscription=.to\b/;
                   },
                   "presence subscribed" => sub {
                       my ($xo, $xml) = @_;
                       return 0 unless $xml =~ /\btype=.subscribed\b/;
                       return 0 unless $xml =~ /\bfrom=.$pb\b/;
                       return 1;
                   },
                   "presence of user" => sub {
                       my ($xo, $xml) = @_;
                       $xml =~ /InitPres/;
                   });


    # now PA is subscribed to PB.  so let's make PB change its status
    $pb->send_xml(qq{<presence><status>PresVer2</status></presence>});

    # let's pretend pa gets confused and asks again, pb's server should
    # reply immediately with the answer
    $xml = $pa->recv_xml;
    like($xml, qr/<presence.+\bfrom=.$pb.+PresVer2/s, "got presver2 presence of pb");

});
