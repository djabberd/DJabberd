#!/usr/bin/perl
use strict;
use Test::More tests => 8;
use lib 't/lib';

require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    # now pa/pb send presence to become available resources
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");
    select(undef, undef, undef, 0.25);

    # PA to PB
    $pa->send_xml(qq{<message from="$pa" to="$pb" id="1"><SOAP-ENV:Envelope xmlns:SOAP-ENV="http://www.w3.org/2001/12/soap-envelope"><SOAP-ENV:Body><x0:foo xmlns:x0="urn:test" /></SOAP-ENV:Body></SOAP-ENV:Envelope></message>});

    my $msg = $pb->recv_xml;
    like($msg, qr/SOAP-ENV:Envelope/, "pb got Envelope in the correct prefix");
    like($msg, qr/xmlns:SOAP-ENV/, "pb got SOAP-ENV prefix decl");
    like($msg, qr/x0:foo/, "pb got foo in the correct prefix");
    like($msg, qr/xmlns:x0/, "pb got x0 prefix decl");

});

