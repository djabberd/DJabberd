#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use IO::Socket::INET6;
use Devel::Peek;
use lib 't/lib';
require 'djabberd-test.pl';

my @client_ports = qw(127.0.0.3:5222 127.0.0.1:11001 127.0.0.2:11001 [::1]:11001 11002 11003);
my @server_ports = qw(127.0.0.3:5269 127.0.0.1:12001 127.0.0.2:12001 [::1]:12001 12002 12003);
my @admin_ports  = qw(127.0.0.3:5200 127.0.0.1:14001 127.0.0.2:14001 [::1]:14001 14002 14003);

my $vhost = DJabberd::VHost->new(
    server_name => 'jabber.example.com',
    s2s         => 0,
    plugins   => [
        DJabberd::Authen::AllowedUsers->new(
            policy => "deny",
            allowedusers => [qw(tester)]
        ),
        DJabberd::Authen::StaticPassword->new(
            password => "password"
        ),
        DJabberd::PresenceChecker::Local->new(),
        DJabberd::Delivery::Local->new(),
        DJabberd::Delivery::S2S->new(),
        DJabberd::RosterStorage::InMemoryOnly->new(),
    ],
);

my $server = DJabberd->new();

foreach my $client_port (@client_ports) {
    $server->add_config_clientport($client_port);
}

foreach my $server_port (@server_ports) {
    $server->add_config_serverport($server_port);
}

foreach my $admin_port (@admin_ports) {
    $server->add_config_adminport($admin_port);
}

$server->add_vhost($vhost);

my $childpid = fork;
if (!$childpid) {
    $0 = "[djabberd]";
    $server->run;
    exit 0;
}

my $err = sub {
    kill 9, $childpid;
    die $_[0];
};

my $conn;

foreach my $addr (@client_ports, @server_ports, @admin_ports) {
    foreach my $try ( 1 .. 3 ) {
        unless ($addr =~ /:\d+$/) {
            $addr = '[::1]:'.$addr;
        }
        diag("Connecting to $addr ...");
        $conn = IO::Socket::INET6->new(
            PeerAddr => $addr,
            Timeout => 1,
        );
        last if $conn;
        sleep 1;
    }
    $err->("Can't connect to server")
        unless $conn;

    $conn->close;
}

END {
    kill 9, $childpid;
}

foreach my $client_port (@client_ports) {
    my $max_connections = 200;
    foreach my $n (1 .. $max_connections) {
    
        my @events;
        my ($handler, $p);
        $handler = DJabberd::TestSAXHandler->new(\@events);
        $p = DJabberd::XMLParser->new( Handler => $handler );
    
        my $get_event = sub {
            while (! @events) {
                my $byte;
                my $rv = sysread($conn, $byte, 1);
                $p->parse_more($byte);
            }
            return shift @events;
        };
    
        my $get_stream_start = sub {
            my $ev = $get_event->();
            die unless $ev && $ev->isa("DJabberd::StreamStart");
            return $ev;
        };
    
        diag("connect $n/$max_connections\n") if $n % 50 == 0;
        unless ($client_port =~ /:\d+$/) {
            $client_port = '[::1]:'.$client_port;
        }
        $conn = IO::Socket::INET6->new(
            PeerAddr => $client_port,
            Timeout => 1,
        );
    
        print $conn qq{
            <stream:stream
              xmlns:stream='http://etherx.jabber.org/streams' to='jabber.example.com'
              xmlns='jabber:client'>
        };
    
        my $ss = $get_stream_start->();
        die unless $ss && $ss->id;
    
        if ($n == 1) {
            ok($ss, "got a stream back");
            ok($ss->id, "got a stream id back");
        }
    
        $p->finish_push;
        $conn->close;
    }
}
