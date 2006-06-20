#!/usr/bin/perl

use strict;
use Test::More tests => 7;
use lib 't/lib';
BEGIN {  $ENV{LOGLEVEL} ||= "FATAL" }
BEGIN { require 'djabberd-test.pl' }

use DJabberd::Authen::InMemoryOnly;

$Test::DJabberd::Server::VHOST_CB = sub {
    my $vh = shift;
    $vh->set_config_inbandreg(1);
};

my $server = Test::DJabberd::Server->new(id => 1);
$server->start([
                DJabberd::RosterStorage::SQLite->new(database => $server->roster),
                DJabberd::Authen::InMemoryOnly->new,
                ]);

eval {
    my $client = Test::DJabberd::Client->new(server => $server, name => "testuser");
    $client->login("foobar");
};
like($@, qr/bad password/, "bad password");


eval {
    my $client = Test::DJabberd::Client->new(server => $server, name => "testuser");
    $client->connect;
    $client->send_xml(qq{<iq type='get' id='reg1'>
                             <query xmlns='jabber:iq:register'/>
                             </iq>});

    my $res = $client->recv_xml;
    like($res, qr/<instructions>/, "got in-band reg instructions");

    $client->send_xml(qq{<iq type='set' id='reg1'>
                             <query xmlns='jabber:iq:register'>
                             <username>testuser</username>
                             <password>jabberwocky</password>
                             </query>
                             </iq>});

    $res = $client->recv_xml;
    like($res, qr/type=.result./, "created account");
};
ok(!$@, "no errors creating account");

my $client = Test::DJabberd::Client->new(server => $server, name => "testuser");
$client->login("jabberwocky");

$client->send_xml("<presence/>");
$client->send_xml("<message type='chat' to='$client'>Hello myself!</message>");
like($client->recv_xml, qr/Hello myself/, "client got own message");

$client->send_xml(qq{<iq type='set' id='unreg1'>
  <query xmlns='jabber:iq:register'>
    <remove/>
  </query>
  </iq>});
like($client->recv_xml, qr/type=.result./, "canceled ourself");
my $res = $client->recv_xml;
like($res, qr/not-authorized/, "got stream close");

