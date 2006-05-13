#!/usr/bin/perl

use strict;
use Test::More tests => 2;
use lib 't/lib';

BEGIN {
    $ENV{LOGLEVEL} = "WARN";
}

require 'djabberd-test.pl';
my $server = Test::DJabberd::Server->new(id => 1);
$server->start;
my $pa = Test::DJabberd::Client->new(server => $server, name => "partya");
$pa->login();
$pa->send_xml("<iq type='get'
    from='$pa/testsuite'
    to='$server'
    id='info1'>
  <query xmlns='http://jabber.org/protocol/disco#info'/>
</iq>");

like($pa->recv_xml(), qr{<identity type='im' category='server' name='djabberd'/>}, "Say we are a server");

$pa->send_xml(qq{<iq type='get'
    from='$pa/testsuite'
    to='$server'
    id='items1'>
  <query xmlns='http://jabber.org/protocol/disco#items'/>
</iq>});

like($pa->recv_xml, qr{<query xmlns='http://jabber.org/protocol/disco#items'/>}, "We dont currently return anything");

END { $server->kill };
