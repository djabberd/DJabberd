#!/usr/bin/perl

use strict;
use Test::More tests => 2;
use lib 't/lib';
require 'djabberd-test.pl';

once_logged_in(sub {
    my $pa = shift;
    my $server = $pa->server;

    my $res = DJabberd::Util::exml($pa->resource);
    $pa->send_xml("<iq type='get'
    from='$pa/$res'
    to='$server'
    id='info1'>
  <query xmlns='http://jabber.org/protocol/disco#info'/>
</iq>");

    like($pa->recv_xml, qr{<identity (?=.*type='im')(?=.*category='server')(?=.*name='djabberd').*/>}, "Say we are a server");

    $pa->send_xml(qq{<iq type='get'
                         from='$pa/$res'
                         to='$server'
                         id='items1'>
                         <query xmlns='http://jabber.org/protocol/disco#items'/>
                         </iq>});

    like($pa->recv_xml, qr{<query xmlns='http://jabber.org/protocol/disco#items'/>}, "We dont currently return anything");
});

