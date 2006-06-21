#!/usr/bin/perl
use strict;
use Test::More tests => 28;
use lib 't/lib';
require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");

    select(undef, undef, undef, 0.25);

    pass "Test case where we send directed presence, then broadcast out unavailable";

    $pa->send_xml(qq{<presence from="$pa/testsuite" to="$pb/testsuite"/>});

    my $xml = $pb->recv_xml;

    like($xml, qr{from=.$pa/testsuite});
    like($xml, qr{to=.$pb/testsuite});
    like($xml, qr{presence});

    $pa->send_xml(qq{<presence><show>this should not go to B</show></presence>});
    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

    pass "Send a directed presence, then a directed unavailable, then verify we don't send broadcast out later";

    $pb->send_xml(qq{<presence to="$pa/testsuite"/>});  # adds $pa to $pb's directed list
    $pb->send_xml(qq{<presence to="$pa/testsuite" type="unavailable"/>}); # removes $pa from $pb's directed list
    select undef, undef, undef, 0.25;

    # $pa should get that $pb is available
    $xml = $pa->recv_xml;
    like($xml, qr{from=.$pb/testsuite});
    like($xml, qr{to=.$pa/testsuite});
    like($xml, qr{presence});

    # $pa should get that $pb is unavailable
    $xml = $pa->recv_xml;
    like($xml, qr{type=.unavailable.});
    like($xml, qr{from=.$pb/testsuite});
    like($xml, qr{to=.$pa/testsuite});
    like($xml, qr{presence});

    # now verify the new presence broadcast doesn't incldue $pa
    $pb->send_xml(qq{<presence from="$pb/testsuite" type="unavailable"/>});
    $pb->send_xml(qq{<message from="$pb/testsuite" to="$pa/testsuite">$pa should get me and not a unavailable packet</message>});

    $xml = $pa->recv_xml;
    like($xml, qr/should get me and not a unavailable packet/, "Make sure we get the message and not the prescence broadcast");

});

