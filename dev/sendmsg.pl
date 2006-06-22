#!/usr/bin/perl
use strict;
use IO::Socket::INET;
use DJabberd::JID;
use DJabberd::ClusterMessage;
use DJabberd::ClusterMessage::DeliverStanza;

my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1:52337')
    or die "no sock";

# bind to a vhost
my $payload = "vhost=jabber.bradfitz.com";
my $encoded = "DJAB" . pack("N", length $payload) . $payload;
print $sock $encoded;

# send a message
my $msg = DJabberd::ClusterMessage::DeliverStanza->new(DJabberd::JID->new('brad@jabber.bradfitz.com'),
                                                       qq{<message
    to='brad\@jabber.bradfitz.com'
    from='juliet\@example.com/balcony'
    type='chat'
  xml:lang='en'>
  <body>Wherefore art thou, Brad?</body>
  </message>});

print $sock $msg->as_packet;
my $encoded = "DJAB" . pack("N", length $payload) . $payload;

my $payload = "Hello world!";
my $encoded = "DJAB" . pack("N", length $payload) . $payload;
print $sock $encoded;
