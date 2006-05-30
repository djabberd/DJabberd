#!/usr/bin/perl

use strict;
use Test::More tests => 15;
use lib 't/lib';
BEGIN { require 'djabberd-test.pl' }

use_ok("DJabberd::Plugin::MUC");

$Test::DJabberd::Server::PLUGIN_CB = sub {
    my $self = shift;
    my $plugins = $self->standard_plugins();
    push @$plugins, DJabberd::Plugin::MUC->new(subdomain => 'conference');
    push @$plugins, DJabberd::Delivery::Local->new, DJabberd::Delivery::S2S->new; # these don't get pushed if someone else touches deliver
    return $plugins;
};


two_parties_one_server(sub {
    my ($pa, $pb) = @_;

    $pa->login;
    my $server = $pa->server;

    $pa->send_xml(qq{
                      <presence to='foobar\@conference.$server/pa'><x xmlns='http://jabber.org/protocol/muc'></x></presence>
                     });


    my $xml = $pa->recv_xml;
    like($xml, qr{from=\'foobar\@conference.$server/pa}, "Got broadcast back that I am in");
    like($xml, qr{affiliation='member'}, "Just a member");
    like($xml, qr"http://jabber.org/protocol/muc#user", "Just a member");


    $pb->login;
    $pb->send_xml(qq{
        <presence to='foobar\@conference.$server/pb'><x xmlns='http://jabber.org/protocol/muc'></x></presence>});

    $xml = $pb->recv_xml;
    $xml .= $pb->recv_xml;

    like($xml, qr{from=\'foobar\@conference.$server/pa}, "Got an initial presence that pa is logged in");
    like($xml, qr{from=\'foobar\@conference.$server/pb}, "Got broadcast back that I am in");
    like($xml, qr{affiliation='member'}, "Just a member");
    like($xml, qr"http://jabber.org/protocol/muc#user", "Just a member");


    $xml = $pa->recv_xml;

    like($xml, qr{from=\'foobar\@conference.$server/pb}, "Got broadcast back that pb logged in");

    like($xml, qr{affiliation='member'}, "Just a member");
    like($xml, qr"http://jabber.org/protocol/muc#user", "Just a member");


    $pa->send_xml(qq { <message
                           from='$pa/testsuite'
                           to='foobar\@conference.$server'
                           type='groupchat'>
                           <body>Sending message from $pa.</body>
                           </message>
                       });


    $xml = $pa->recv_xml;

    like($xml, qr"Sending message from $pa", "Got my own message back");
    like($xml, qr"from=.foobar\@conference.$server/pa.", "Got my own message back");

    $xml .= $pb->recv_xml;
    like($xml, qr"Sending message from $pa", "Got message from pa");
    like($xml, qr"from=.foobar\@conference.$server/pa.", "From the right user");

});



