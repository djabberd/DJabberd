#!/usr/bin/perl


use strict;
use Test::More tests => 11;
use lib 't/lib';
#BEGIN {  $ENV{LOGLEVEL} ||= "FATAL" }
BEGIN { require 'djabberd-test.pl' }



use_ok("DJabberd::Plugin::VCard");


$Test::DJabberd::Server::PLUGIN_CB = sub {
    my $self = shift;
    my $plugins = $self->standard_plugins();
    push @$plugins, DJabberd::Plugin::VCard->new(storage => $self->roster_name);
    return $plugins;
};

#really there should be a way to set plugins before this runs so I could just use once_logged_in
two_parties( sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    $pa->send_xml("<iq type='get'
    from='$pa/testsuite'
    to='" . $pa->server . "'
    id='info1'>
  <query xmlns='http://jabber.org/protocol/disco#info'/>
</iq>");
    like($pa->recv_xml, qr{vcard-temp}, "vcard");


    $pa->send_xml("<iq
    from='$pa/testsuite'
    type='get'
    id='v1'>
  <vCard xmlns='vcard-temp'/>
</iq>");


    my $xml = $pa->recv_xml;


    like($xml, qr{<vCard xmlns='vcard-temp'/>}, "No vcard set, getting empty vcard back");
    $pa->send_xml("<iq
    from='$pa/testsuite'
    type='set'
    id='v2'>
  <vCard xmlns='vcard-temp'><FN>Test User</FN></vCard>
</iq>");

    $xml = $pa->recv_xml;
    like($xml, qr/result/, "Got a result back on the set");


    $pa->send_xml("<iq
    from='$pa/testsuite'
    type='get'
    id='v3'>
  <vCard xmlns='vcard-temp'/>
</iq>");

    $xml = $pa->recv_xml;
    like($xml, qr{Test User}, "Got the vcard back");



    $pb->send_xml("<iq
    from='$pb/testsuite'
    to='$pa'
    type='get'
    id='v1'>
  <vCard xmlns='vcard-temp'/>
</iq>");

    $xml = $pb->recv_xml;
    like($xml, qr{Test User}, "Got the vcard back to user pb from pa");
});


