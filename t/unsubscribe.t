#!/usr/bin/perl
use strict;
use Test::More qw(no_plan);
use lib 't/lib';
require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    $pa->initial_presence;
    $pb->initial_presence;
    $pa->get_roster;
    $pb->get_roster;

    $pa->subscribe_to($pb);
    $pb->accept_subscription_from($pa);

    $pb->subscribe_to($pa);
    $pa->accept_subscription_from($pb);



    $pb->send_xml(qq{<presence><status>PresVer2</status></presence>});
    my $xml = $pa->recv_xml;
    like($xml, qr/<presence.+\bfrom=.$pb.+PresVer2/s, "$pa gets $pb presence");

    $pa->send_xml(qq{<presence><status>PresVer3</status></presence>});
    $xml = $pb->recv_xml;
    like($xml, qr/<presence.+\bfrom=.$pa.+PresVer3/s, "$pb gets $pa presencs");


    # now lets try unsubscribe from




});
