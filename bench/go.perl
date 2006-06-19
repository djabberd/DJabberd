#!/usr/bin/perl

use strict;
use Test::More tests => 8;
use blib;
use lib 't/lib';
use GTop;

require 'djabberd-test.pl';

my $server = Test::DJabberd::Server->new( id => 1 );
$server->start;

my @clients;

my $one = Test::DJabberd::Client->new(server => $server, name => gen_client_id() );
my $two = Test::DJabberd::Client->new(server => $server, name => gen_client_id() );

push @clients, $one, $two;

while (1) {
    last if @clients > 5000;
    foreach (1..20) {
	$one = $two;
	$two = Test::DJabberd::Client->new(server => $server, name => gen_client_id() );
	push @clients, $two;
    }
    my $gtop = GTop->new;
    my $proc_mem = $gtop->proc_mem( $server->{pid} );
    printf( "[%d]\tPid:%d Flags:%s Size:%s VSize:%s Resident:%s Share:%s RSS:%s RSSLimit:%s\n",
	    scalar @clients,
	    $server->{pid},
	    $proc_mem->flags,
	    $proc_mem->size,
	    $proc_mem->vsize,
	    $proc_mem->resident,
	    $proc_mem->share,
	    $proc_mem->rss,
	    $proc_mem->rss_rlim,
	    );
   system( "ps", "l", "-p", $server->{pid} );
    sleep 1;
}

$server->kill;

{
    my $counter = 0;
    sub gen_client_id {
	return "client_" . $counter++;
    }
}
