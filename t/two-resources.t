#!/usr/bin/perl
use strict;
use Test::More tests => 16;
use lib 't/lib';
require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    $pa->subscribe_successfully($pb);

    my $pa2 = Test::DJabberd::Client->new(server => $pa->server,
                                          name => "partya",
                                          resource => "conn2",
                                          );
    $pa2->login;

    $pb->send_xml(qq{<presence><status>BisHere</status></presence>});

    # both of A's resources should get it.
    my $xml = $pa2->recv_xml;
    like($xml, qr{BisHere}, "partya2 got B's presence");
    $xml = $pa->recv_xml;
    like($xml, qr{BisHere}, "partya1 got B's presence");

    # both of A's resources should get a message from pb to pa's bare JID
    unlike("$pa", qr!/!, "stringification of pa doesn't include a resource");
    $pb->send_xml("<message type='chat' to='$pa'>HelloMsg from $pb.</message>");
    like($pa->recv_xml,  qr{HelloMsg from}, "message to pa from pb");
    like($pa2->recv_xml, qr{HelloMsg from}, "message to pa2 from pb");

    # sent a message to a specific JID
    $pb->send_xml("<message type='chat' to='$pa/testsuite'>you are testsuite</message>");
    $pb->send_xml("<message type='chat' to='$pa/conn2'>you are conn2</message>");
    like($pa->recv_xml,  qr{you are testsuite}, "pa got uniq message");
    like($pa2->recv_xml, qr{you are conn2}, "pb got uniq message");


});
