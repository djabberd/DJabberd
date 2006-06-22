#!/usr/bin/perl
use strict;
use IO::Socket::INET;

my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1:52337')
    or die "no sock";

my $payload = "Hello, world!";
my $encoded = "DJAB" . pack("N", length $payload) . $payload;

print $sock "$encoded" x 5;
