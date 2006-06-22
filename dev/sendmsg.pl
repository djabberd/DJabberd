#!/usr/bin/perl
use strict;
use IO::Socket::INET;
use DJabberd::ClusterMessage;

my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1:52337')
    or die "no sock";

# bind to a vhost
my $payload = "vhost=jabber.bradfitz.com";
my $encoded = "DJAB" . pack("N", length $payload) . $payload;
print $sock $encoded;

# send a message
my $msg = DJabberd::ClusterMessage->new;
print $sock $msg->as_packet;
my $encoded = "DJAB" . pack("N", length $payload) . $payload;

my $payload = "Hello world!";
my $encoded = "DJAB" . pack("N", length $payload) . $payload;
print $sock $encoded;
