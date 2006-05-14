#!/usr/bin/perl


use strict;
use Test::More tests => 4;
use lib 't/lib';
BEGIN {  $ENV{LOGLEVEL} ||= "FATAL" }
BEGIN { require 'djabberd-test.pl' }

use DJabberd::Authen::HTDigest;

my $server = Test::DJabberd::Server->new(id => 1);
$server->start([
        DJabberd::RosterStorage::SQLite->new(database => $server->roster),
        DJabberd::Authen::HTDigest->new(realm => 'djabberd', htdigest => 't/htdigest.t.conf')
        ]);

eval {
    my $client = Test::DJabberd::Client->new(server => $server, name => "testuser");
    $client->login("foobar");
};
like($@, qr/bad password/, "bad password");

eval {
    my $client = Test::DJabberd::Client->new(server => $server, name => "testuser2");
    $client->login("foo");
};
like($@, qr/bad password/, "correct password wrong username");


my $client = Test::DJabberd::Client->new(server => $server, name => "testuser");
$client->login("foo");
pass("Client logged in");


eval {
    my $server2 = Test::DJabberd::Server->new(id => 1);
    $server2->{plugins} = [
                           DJabberd::RosterStorage::SQLite->new(database => $server->roster),
                           DJabberd::Authen::HTDigest->new(realm => 'djabberd', htdigest => 't/htdigest.t.conf.shouldnotbehere')
                           ];
    $server2->start();
};
like($@, qr/does not exist/,  "File should not be here, ignore previous line");


END { $server->kill }


