#!/usr/bin/perl
use strict;
use warnings;

use Danga::Socket;
use Test::More tests => 12;
#use Test::SharedFork;
#use Test::TCP;
use Net::DNS::Nameserver;
use lib 't/lib';
require 'djabberd-test.pl';

eval {
    require Test::SharedFork;
    Test::SharedFork->import;
    require Test::TCP;
    Test::TCP->import;
};
SKIP: {
	skip('Missing test prerequisites', 12) if($@);
my $ns_host = '127.0.0.1';
my $ns_port = Test::TCP::empty_port();
my $nameserver = $ns_host.q{:}.$ns_port;
#print "Nameserver is at $nameserver\n";

# Start Mock-Up DNS Server
my $childpid_dns = fork;
if(!$childpid_dns) {
    my $reply_handler = sub {
        my ($qname, $qclass, $qtype, $peerhost,$query,$conn) = @_;
	my ($rcode, @ans, @auth, @add);
        
        #print 'Received query from '.$peerhost.' to '. $conn->{sockhost}. "\n";
	#$query->print;

	if ($qtype eq 'AAAA' && $qname eq 'www.ripe.net' ) {
		my ($ttl, $rdata) = (3600, '2001:67c:2e8:22:0:0:c100:68b');
		my $rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
		$rcode = 'NOERROR';
        } elsif ($qtype eq 'A' && $qname eq 'www.ripe.net' ) {
		my ($ttl, $rdata) = (3600, '193.0.6.139');
		my $rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
		$rcode = 'NOERROR';
        } elsif ($qtype eq 'SRV' && $qname eq '_xmpp-server._tcp.amessage.info' ) {
		my ($ttl, $rdata) = (3600, '5 1 5269 s2s.amessage.eu');
		my $rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
		$rcode = 'NOERROR';
        } elsif ($qtype eq 'A' && $qname eq 's2s.amessage.eu' ) {
		my ($ttl, $rdata) = (3600, '176.9.123.253');
		my $rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
		$rcode = 'NOERROR';
        } elsif ($qtype eq 'AAAA' && $qname eq 's2s.amessage.eu' ) {
		my ($ttl, $rdata) = (3600, '2a01:4f8:151:82e3::2');
		my $rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
		$rcode = 'NOERROR';
        } elsif ($qtype eq 'SRV' && $qname eq '_xmpp-server._tcp.google.com' ) {
		my ($ttl, $rdata) = (3600, '5 0 5269 xmpp-server.l.google.com');
		my $rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
                ($ttl, $rdata) = (3600, '20 0 5269 alt1.xmpp-server.l.google.com');
		$rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
                ($ttl, $rdata) = (3600, '20 0 5269 alt2.xmpp-server.l.google.com');
		$rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
                ($ttl, $rdata) = (3600, '20 0 5269 alt3.xmpp-server.l.google.com');
		$rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
                ($ttl, $rdata) = (3600, '20 0 5269 alt4.xmpp-server.l.google.com');
		$rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
		$rcode = 'NOERROR';
        } elsif ($qtype eq 'A' && $qname =~ m/xmpp-server.l.google.com$/ ) {
		my ($ttl, $rdata) = (3600, '74.125.142.125');
		my $rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
		$rcode = 'NOERROR';
	} elsif ( $qname eq 'www.ripe.net' ) {
		$rcode = 'NOERROR';
	} else {
		$rcode = 'NXDOMAIN';
	}
        
        #print "Sending Reply for $qname/$qtype - $rcode - ".join(':', map { $_->string } @ans)."\n";

	# mark the answer as authoritive (by setting the 'aa' flag
	return ($rcode, \@ans, \@auth, \@add, { aa => 1 });
    };
    
    my $ns = Net::DNS::Nameserver->new(
        LocalPort       => $ns_port,
        ReplyHandler    => $reply_handler,
        Verbose         => 0,
    );
    
    $ns->main_loop;
    exit 0;
}

sleep 1;

DJabberd::DNS->new(
    hostname => 'www.ripe.net',
    port     => 1,
    callback => sub {
        my $endpt = shift;
        ok($endpt,'Got an Endpoint');
        isa_ok($endpt,'DJabberd::IPEndPoint');
        is($endpt->addr(),'2001:67c:2e8:22:0:0:c100:68b','Got the expected IPv6 address for www.ripe.net AAAA');
    },
    nameserver => $nameserver,
);

DJabberd::DNS->a(
    hostname => 'www.ripe.net',
    port     => 1,
    callback => sub {
        my $endpt = shift;
        ok($endpt,'Got an Endpoint');
        isa_ok($endpt,'DJabberd::IPEndPoint');
        is($endpt->addr(),'193.0.6.139','Got the expected IPv4 address 193.0.6.139 for www.ripe.net A');
    },
    nameserver => $nameserver,
);

DJabberd::DNS->srv(
    domain => 'amessage.info',
    service => '_xmpp-server._tcp',
    port     => 1,
    callback => sub {
        my $endpt = shift;
        ok($endpt,'Got an Endpoint');
        isa_ok($endpt,'DJabberd::IPEndPoint');
        is($endpt->addr(),'2a01:4f8:151:82e3:0:0:0:2','Got the expected IPv6 address for _xmpp-server._tcp.amessage.info SRV');
    },
    nameserver => $nameserver,
);

DJabberd::DNS->srv(
    domain => 'google.com',
    service => '_xmpp-server._tcp',
    port     => 1,
    callback => sub {
        my $endpt = shift;
        ok($endpt,'Got an Endpoint');
        isa_ok($endpt,'DJabberd::IPEndPoint');
        like($endpt->addr(), qr/^\d+\.\d+\.\d+\.\d+$/,'Got the expected IPv4 address for _xmpp-server._tcp.google.com SRV');
    },
    nameserver => $nameserver,
);

# Start Event Socket
my $childpid_sock = fork;
if (!$childpid_sock) {
    Danga::Socket->EventLoop();
    exit 0;
}

sleep 2;

END {
    kill 9, $childpid_sock if $childpid_sock;
    kill 9, $childpid_dns if $childpid_dns;
}
}
