#!/usr/bin/perl

use strict;
use Test::More tests => 14;
use lib 't/lib';

BEGIN {
    $ENV{LOGLEVEL} ||= "FATAL";
    require 'djabberd-test.pl';
}

my $expect_crash;

$Test::DJabberd::Server::VHOST_CB = sub {
    my $vhost = shift;
    $vhost->set_config_quirksmode(1);
    $expect_crash = 0;
};
run_test();

$Test::DJabberd::Server::VHOST_CB = sub {
    my $vhost = shift;
    $vhost->set_config_quirksmode(0);
    $expect_crash = 1;
};
run_test();


sub run_test {
    two_parties(sub {
        my ($pa, $pb) = @_;
        $pa->login;
        $pb->login;
        my $xml;

        $pa->send_xml("<iq
    from='$pa/testsuite'
    to='$pb/testsuite'
    type='get'
    id='v1'>
  <vCard xmlns='vcard-temp'/>
</iq>");


        $xml = $pb->recv_xml;
        like($xml, qr{<vCard xmlns='vcard-temp'/>}, "iq vcard query");
        like($xml, qr{\btype=.get\b}, "is a get");

        # now we'll make pb be the broken libgaim.  note the bogus from address.
        $pb->send_xml("<iq
    from='$pa/testsuite'
    to='$pa/testsuite'
    type='error'
    id='v1'>
  <vCard xmlns='vcard-temp'/>
</iq>");

        if ($expect_crash) {
            $xml = $pb->recv_xml;
            like($xml, qr{invalid-from}, "got invalid from stream error");
            return;
        }

        # with quirks mode enabled (the default), this will make it through.
        $xml = $pa->recv_xml;
        like($xml, qr/\btype=.error\b/, "Got an error back");

        # and pb is still connected.
        $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
        like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

    });
}
