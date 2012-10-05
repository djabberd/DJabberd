#!/usr/bin/perl
use strict;
use warnings;

use IO::Socket::INET6;
use Test::More tests => 3;
use lib 't/lib';
BEGIN {  $ENV{LOGLEVEL} ||= "FATAL" }
BEGIN { require 'djabberd-test.pl' }

my $adminhost = '::1';
my $adminport = 23090;

my $server = Test::DJabberd::Server->new(id => 1);
$server->{adminport} = $adminport;
$server->start();

my $addr = '['.$adminhost.']:'.$adminport;

select(undef, undef, undef, 0.25);

my $sock = IO::Socket::INET6->new(
    PeerAddr    => $adminhost,
    PeerPort    => $adminport,
    Timeout     => 1,
) or die "Cannot connect to server " . $server->id . " ($addr)";
diag('Connected to '.$addr);

$sock->write("list vhosts\n");

my $line = $sock->getline;
like($line, qr/$server/, "Get the vhost back");

like($sock->getline, qr/\./, "And a terminator" );

$sock->write("counters\r\n");
my $got_end = 0;
my $buffer;
while (my $line = $sock->getline) {
    if ($line =~ /^\./) {
        $got_end = 1;
        last;
    }
    $buffer .= $line;
}

ok($got_end, "counters terminated in dot");
