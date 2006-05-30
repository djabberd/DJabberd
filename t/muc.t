#!/usr/bin/perl

use strict;
use Test::More tests => 2;
use lib 't/lib';



require 'djabberd-test.pl';
once_logged_in(sub {
    my $pa = shift;
    my $server = $pa->server;
    $pa->send_xml(qq{
                      <presence to='foobar\@crucially.net/foo'><x xmlns='http://jabber.org/protocol/muc'></x></presence>
                     });

    diag $pa->recv_xml();
});



