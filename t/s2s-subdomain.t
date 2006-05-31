#!/usr/bin/perl
use strict;
use Test::More qw(no_plan);
use lib 't/lib';

require 'djabberd-test.pl';



$SIG{'ALRM'} = sub { local $TODO = 'Currently not working'; fail("3 seconds timeout, did not succed"); die "alarm reached" };

@Test::DJabberd::Server::SUBDOMAINS = qw(subdomain);

two_parties_s2s(sub {
    alarm(3);
    eval {
        my ($pa, $pb) = @_;
        #very much fake subdomain issue
        $pa->login;
        $pb->login;

        # PA to PB


        $pa->server->{hostname} = 'subdomain.' . $pa->server->hostname;

        $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
        like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

        # PB to PA
        $pb->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
        like($pa->recv_xml, qr/Hello back/, "pa got pb's message");
    };
    if($@ and $@ !~/alarm reached/) {
        die $@;
    }
});


