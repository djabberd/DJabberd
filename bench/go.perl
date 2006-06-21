#!/usr/bin/perl

use strict;
use blib;
use lib 't/lib';
use GTop;
use Time::HiRes qw(time);

require 'djabberd-test.pl';

my $server = Test::DJabberd::Server->new( id => 1 );
$server->start;

my $pid = fork;

unless (defined $pid) {
    die "Fork failed\n";
}

if ($pid) {
    while (1) {
	my $gtop = GTop->new;
	my $proc_mem = $gtop->proc_mem( $server->{pid} );
	printf( "Flags:%s Size:%s VSize:%s Resident:%s Share:%s RSS:%s RSSLimit:%s\n",
		$proc_mem->flags,
		$proc_mem->size,
		$proc_mem->vsize,
		$proc_mem->resident,
		$proc_mem->share,
		$proc_mem->rss,
		$proc_mem->rss_rlim,
		);
	sleep 1;
    }
}

fork; fork; fork; fork;

my @clients;

warn "[$$] Connecting 25 clients";

while (@clients < 25) {
    my $client = Test::DJabberd::Client->new(server => $server, name => gen_client_id() );
    $client->login;
    push @clients, $client;
}

warn "[$$] Sending presence";

foreach my $client (@clients) {
    $client->send_xml("<presence/>");
}

warn "[$$] Passing messages";

my $prevclient = $clients[0];
my $prevtime = time;
while (1) {
    my $timediff = time - $prevtime;
    my $numclients = scalar @clients;

    warn "[$$] Time for " . $numclients . " clients: " . $timediff . " (" . $numclients / $timediff . "/sec)";

    $prevtime = time;

    foreach my $client (@clients) {
	$prevclient->send_xml( qq(<message type="chat" to="$client">Hello you</message>) );
	my $output = $client->recv_xml;
	$prevclient = $client;
    }
}

END {
    $server->kill;
}

{
    my $counter = 0;
    sub gen_client_id {
	return "client_${$}_" . $counter++;
    }
}
