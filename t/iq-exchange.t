#!/usr/bin/perl
use strict;
use Test::More tests => 8;
use lib 't/lib';

require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;
    $pa->send_xml("<presence/>");
    like($pa->recv_xml, qr/from=["']$pa/, "own presence check");
    $pb->send_xml("<presence/>");
    like($pb->recv_xml, qr/from=["']$pb/, "own presence check");
    select(undef,undef,undef,0.25);

    my $ja = DJabberd::JID->new($pa.'/'.$pb->resource);
    my $jb = DJabberd::JID->new($pb.'/'.$pb->resource);
    $pa->send_xml("<iq type='get' id='pa1' to='$jb'><x/></iq>");
    like($pb->recv_xml, qr/id=.pa./, "pb got pa's iq");
    $pb->send_xml("<iq type='get' id='pb1' to='$ja'><x/></iq>");
    like($pa->recv_xml, qr/id=.pb./, "pb got pa's iq");


});

