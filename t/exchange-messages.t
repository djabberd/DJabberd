#!/usr/bin/perl
use strict;
use Test::More tests => 10;
use lib 't/lib';

require 'djabberd-test.pl';

two_parties(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    # pb isn't yet an available resource, so should not get the message
    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    my $response = $pb->recv_xml(1.5);
    $response = '' unless defined $response;
    unlike($response, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb getting message as unavailable resource");

    # now pa/pb send presence to become available resources
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");
    select(undef, undef, undef, 0.25);

    # PA to PB
    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

    # PB to PA
    $pb->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
    like($pa->recv_xml, qr/Hello back/, "pa got pb's message");

    # PB to PA with some gibberish that iChat made
    $pb->send_xml(qq{<message to="$pa" type="chat" id="iChat_3B808FAB">
<body>so many&#16; say &quot;seconds&quot;</body>
<html xmlns="http://jabber.org/protocol/xhtml-im"><body xmlns="http://www.w3.org/1999/xhtml" style="background-color:#EBEBEB;color:#000000"><span style="font-family:Helvetica">so many&#16; say &quot;seconds&quot;</span></body></html><x xmlns="jabber:x:event">
<composing/>
</x>
</message>});
    like($pa->recv_xml, qr/so many/, "pa got pb's iChat-made message");

    # PA to self
    $pa->send_xml("<message type='chat' to='$pa'>Hello myself!</message>");
    like($pa->recv_xml, qr/Hello myself/, "pa got own message");

});

