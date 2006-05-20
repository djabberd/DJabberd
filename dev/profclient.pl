#!/usr/bin/perl
use strict;
#use Devel::Profiler;
use lib '../lib';
use lib '../t/lib';
require 'djabberd-test.pl';

my $server = Test::DJabberd::Server->new(clientport => 5222,
                                         hostname => "example.com",
                                         id => 1);

my $pa = Test::DJabberd::Client->new(server => $server, name => "partya");
my $pb = Test::DJabberd::Client->new(server => $server, name => "partyb");

    $pa->login;
    $pb->login;

    for (1..333) {
        print "$_\n" if $_ % 50 == 0;
        # PA to PB
        $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
        like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

        # PB to PA
        $pb->send_xml("<message type='chat' to='$pa'>Hello back! xxxxxxxxxxxxxx xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx</message>");
        like($pa->recv_xml, qr/Hello back/, "pa got pb's message");

        # PA to self
        $pa->send_xml(qq{<message type="chat" to="$pa">
<x xmlns="jabber:x:event">
<composing/>
</x>
<body>Hello self xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx x  x x  x  !</body>
<html xmlns="http://jabber.org/protocol/xhtml-im">
<body xmlns="http://www.w3.org/1999/xhtml">
<html>Hello <b>self OMG</b>xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx x  x x  x x x!</html>
</body>
</html>
</message>});
        like($pa->recv_xml, qr/Hello self/, "pa got own message");
    }



sub like {
    my ($val, $regexp, $msg) = @_;
    $val =~ /$regexp/ or die "Failed: $msg";
}
