#!/usr/bin/perl


use strict;
use Test::More tests => 26;
use lib 't/lib';
#BEGIN {  $ENV{LOGLEVEL} ||= "FATAL" }
BEGIN { require 'djabberd-test.pl' }

$ENV{DJABBERD_TEST_SQLITE} ||= 1 unless exists($ENV{DJABBERD_TEST_SQLITE});


SKIP: {
    skip "Not testing DJabberd::Plugin::VCard::SQLite", 13 unless $ENV{DJABBERD_TEST_SQLITE};
    use_ok("DJabberd::Plugin::VCard::SQLite");
    $Test::DJabberd::Server::PLUGIN_CB = sub {
        my $self = shift;
        my $plugins = $self->standard_plugins();
        push @$plugins, DJabberd::Plugin::VCard::SQLite->new(storage => $self->roster_name);
        return $plugins;
    };

    run_tests();
}



use_ok("DJabberd::Plugin::VCard::InMemoryOnly");


$Test::DJabberd::Server::PLUGIN_CB = sub {
    my $self = shift;
    my $plugins = $self->standard_plugins();
    push @$plugins, DJabberd::Plugin::VCard::InMemoryOnly->new();
    return $plugins;
};

run_tests();

#really there should be a way to set plugins before this runs so I could just use once_logged_in
sub run_tests {
    two_parties( sub {
        my ($pa, $pb) = @_;
        $pa->login;
        $pb->login;
        $pa->send_xml("<presence/>");
        $pb->send_xml("<presence/>");

        my $e_pa_res = DJabberd::Util::exml($pa->resource);
        my $e_pb_res = DJabberd::Util::exml($pb->resource);

        $pa->send_xml("<iq type='get'
    from='$pa/$e_pa_res'
    to='" . $pa->server . "'
    id='info1'>
  <query xmlns='http://jabber.org/protocol/disco#info'/>
</iq>");
        like($pa->recv_xml, qr{vcard-temp}, "vcard");


        $pa->send_xml("<iq
    from='$pa/$e_pa_res'
    type='get'
    id='v1'>
  <vCard xmlns='vcard-temp'/>
</iq>");


        my $xml = $pa->recv_xml;


        like($xml, qr{<vCard xmlns='vcard-temp'/>}, "No vcard set, getting empty vcard back");
        $pa->send_xml("<iq
    from='$pa/$e_pa_res'
    type='set'
    id='v2'>
  <vCard xmlns='vcard-temp'><FN>Test User</FN></vCard>
</iq>");

        $xml = $pa->recv_xml;
        like($xml, qr/result/, "Got a result back on the set");


        $pa->send_xml("<iq
    from='$pa/$e_pa_res'
    type='get'
    id='v3'>
  <vCard xmlns='vcard-temp'/>
</iq>");

        $xml = $pa->recv_xml;
        like($xml, qr{Test User}, "Got the vcard back");



        $pb->send_xml("<iq
    from='$pb/$e_pb_res'
    to='$pa'
    type='get'
    id='v1'>
  <vCard xmlns='vcard-temp'/>
</iq>");

        $xml = $pb->recv_xml;
        like($xml, qr{Test User}, "Got the vcard back to user pb from pa");

    # some clients send iqs before presence, they should get responses even when they are unavailable

        $pa->send_xml("<presence type='unavailable'/>");
        $pa->send_xml("<iq
    from='$pa/$e_pa_res'
    type='get'
    id='v1'>
  <vCard xmlns='vcard-temp'/>
</iq>");


        $xml = $pa->recv_xml(2);
        like($xml, qr{Test User}, "Got the vcard back even when unavailable");

    });
}


