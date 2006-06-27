#!/usr/bin/perl

use strict;
use blib;
use lib 't/lib';
use GTop;
use Time::HiRes qw(time);
use Data::Dumper;
$SIG{INT} = sub {
#    warn Dumper(\%Danga::Socket::DescriptorMap);
    warn "xmlparsers existing = $DJabberd::XMLParser::instance_count\n";
    exit (0);
};

require 'djabberd-test.pl';

my $server = Test::DJabberd::Server->new( id => 1 );
$server->start;
sleep 1;
delete $SIG{INT};

print "server pid = $server->{pid}\n";

my $gtop = GTop->new;
my $gdump = sub {
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
};
$gdump->();

my @clients;
my $n = 0;
while ($n++ < 100_000) {
    my $client = Test::DJabberd::Client->new(server => $server,
                                             name => gen_client_id(),
                                             resource => "conn$n");
    $client->login;
    $client->send_xml("<presence/>");
    push @clients, $client;
    if ($n % 100 == 0) {
        warn "$n..\n";
        $gdump->();

        if (0 && $n == 500) {
            @clients = ();
            warn "Killed 'em all.\n";
            $gdump->();
            sleep 1;
            sleep 1;
            $gdump->();
        }

    }

    if (0) {
        use Devel::Size;
        my %size;
        $size{_base} = Devel::Size::size($client);
        foreach my $k (keys %$client) {
            next if $k =~ /^vhost|server|parser|jabberhandler|id|fd|log|xmllog$/;
            my $thissize = Devel::Size::total_size($client->{$k});
            $size{$k} = $thissize;
        }
        my $sum = 0;
        foreach my $k ( sort { $size{$b} <=> $size{$a} } keys %size) {
            printf " %5d $k\n", $size{$k};
            $sum += $size{$k};
        }
        print "SUM = $sum\n";
        use Devel::Peek;
        Dump($client->{sock});
    }


    #print "XML parsers: $DJabberd::XMLParser::instance_count\n";
}

use Devel::Size;
print "size = ", Devel::Size::total_size(\@clients), "\n";


$gdump->();
warn "sleeping.\n";
sleep 30;

{
    my $counter = 0;
    sub gen_client_id {
        return "client_${$}_" . $counter++;
    }
}
