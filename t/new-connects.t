#!/usr/bin/perl

use strict;
use lib 'lib';
use Test::More 'no_plan';

BEGIN {
    $ENV{LOGLEVEL} = "WARN";
}

use DJabberd;
use DJabberd::Authen::AllowedUsers;
use DJabberd::Authen::StaticPassword;
use DJabberd::TestSAXHandler;
use DJabberd::RosterStorage::InMemoryOnly;
use FindBin qw($Bin);

my $client_port = 11001;

my $vhost = DJabberd::VHost->new(
                                 server_name => 'jabber.example.com',
                                 s2s         => 0,
                                 plugins   => [
                                               DJabberd::Authen::AllowedUsers->new(policy => "deny",
                                                                                   allowedusers => [qw(tester)]),
                                               DJabberd::Authen::StaticPassword->new(password => "password"),
                                               DJabberd::PresenceChecker::Local->new(),
                                               DJabberd::Delivery::Local->new(),
                                               DJabberd::Delivery::S2S->new(),
                                               DJabberd::RosterStorage::InMemoryOnly->new(),
                                               ],
                                 );

my $server = DJabberd->new;

$server->set_config_clientport($client_port);
$server->set_config_serverport($client_port+1);

$server->add_vhost($vhost);

my $childpid = fork;
if (!$childpid) {
    $0 = "[djabberd]";
    $server->run;
    exit 0;
}

use IO::Socket::INET;
my $conn;

foreach (1..3) {
    print "Connecting...\n";
    $conn = IO::Socket::INET->new(PeerAddr => "127.0.0.1:$client_port", Timeout => 1);
    last if $conn;
    sleep 1;
}

my $err = sub {
    kill 9, $childpid;
    die $_[0];
};

END {
    kill 9, $childpid;
}

$err->("Can't connect to server") unless $conn;

use Devel::Peek;

$conn->close;
for my $n (1..500) {

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

    diag("connect $n/500\n") if $n % 50 == 0;
    $conn = IO::Socket::INET->new(PeerAddr => "127.0.0.1:$client_port", Timeout => 1);

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

