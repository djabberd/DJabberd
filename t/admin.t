#!/usr/bin/perl


use strict;
use Test::More tests => 2;
use lib 't/lib';
BEGIN {  $ENV{LOGLEVEL} ||= "FATAL" }
BEGIN { require 'djabberd-test.pl' }

my $adminport = 23090;

my $server = Test::DJabberd::Server->new(id => 1);
$server->{adminport} = $adminport;
$server->start();


my $addr = "127.0.0.1:$adminport";

select(undef, undef, undef, 0.25);

my $sock = IO::Socket::INET->new(PeerAddr => "$addr",
                                 Timeout => 1)
    or die "Cannot connect to server " . $server->id . " ($addr)";



$sock->write("list vhosts\n");

my $line = $sock->getline;
like($line, qr/Welcome to DJabberd/, "Get a hello back");

like($sock->getline, qr/$server/, "Got the vhost back" );
