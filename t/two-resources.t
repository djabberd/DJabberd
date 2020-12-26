#!/usr/bin/perl
use strict;
use Test::More tests => 30;
use lib 't/lib';
BEGIN { $ENV{LOGLEVEL} = 'FATAL'; }
require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;
    $pa->send_xml("<presence><status>PA1IsHere</status></presence>");
    $pb->send_xml("<presence/>");
    select(undef,undef,undef,0.25);

    $pa->subscribe_successfully($pb);

    my $xml;

    my $pa2 = Test::DJabberd::Client->new(server   => $pa->server,
                                          name     => $pa->username,
                                          resource => "conn2",
                                          );
    $pa2->login;
    $pa2->send_xml("<presence><status>PA2IsHere</status></presence>");

    # The first thing pa2 will see after sending that presence stanza
    # is the presence of pa1, which the server injects in there.
    $xml = $pa2->recv_xml;
    like($xml, qr{PA1IsHere}, "partya2 now knows of partya1 being online");

    $xml = $pa2->recv_xml;
    like($xml, qr{^<presence.+from=.partyb}, "partya2 now also knows of partyb being online");

    # pa1 gets the presence from pa2
    $xml = $pa->recv_xml;
    like($xml, qr{PA2IsHere}, "partya1 now knows of partya2 being online");

    $pb->send_xml(qq{<presence><status>BisHere</status></presence>});

    # both of A's resources should get it.
    $xml = $pa->recv_xml;
    like($xml, qr{BisHere}, "partya1 got B's presence");
    $xml = $pa2->recv_xml;
    like($xml, qr{BisHere}, "partya2 got B's presence");

    # both of A's resources should get a message from pb to pa's bare JID
    unlike("$pa", qr!/!, "stringification of pa doesn't include a resource");
    $pb->send_xml("<message type='chat' to='$pa'>HelloMsg from $pb.</message>");
    like($pa->recv_xml,  qr{HelloMsg from}, "message to pa from pb");
    like($pa2->recv_xml, qr{HelloMsg from}, "message to pa2 from pb");

    # sent a message to a specific JID
    my $e_pa_res = DJabberd::Util::exml($pa->resource);
    $pb->send_xml("<message type='chat' to='$pa/$e_pa_res'>you are testsuite</message>");
    $pb->send_xml("<message type='chat' to='$pa/conn2'>you are conn2</message>");
    like($pa->recv_xml,  qr{you are testsuite}, "pa got uniq message");
    like($pa2->recv_xml, qr{you are conn2}, "pb got uniq message");

    # TODO: try connecting a third $pa, but with a dup resource, and
    # watch it get bitch slapped

    my $pa3 = Test::DJabberd::Client->new(server   => $pa2->server,
                                          name     => $pa2->username,
                                          resource => $pa2->resource,
                                          );
    $pa3->login;
    $pa3->send_xml("<presence/>");

    like($pa2->recv_xml, qr{conflict}, "got stream conflict error");
    is($pa2->get_event(2, 1),"end-stream", "got closed stream");

    # TODO: test that conn2 goes unavailable, then sending a message to /conn2 should
    # really act as if it's to a barejid, and go to all available resources.
    # -- we need the test and the implementation

});
