#!/usr/bin/perl

use strict;
use Test::More tests => 7;
use lib 't/lib';
require 'djabberd-test.pl';

my $client_port = 11001;
my $sock_path = '/tmp/_test_djabberd.sock';
my $grp = [split(/\s+/,`groups`)]->[0];
my $client_path = "$sock_path g+$grp";

$ENV{LOGLEVEL} = $ENV{TEST_LOG} || 'WARN';
DJabberd::Log::set_logger("main");

my $vhost = DJabberd::VHost->new(
                                 server_name => 'jabber.example.com',
				 require_ssl => 1,
                                 s2s         => 0,
                                 plugins     => [
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
unlink($sock_path);
`touch "/tmp/_test_djabberd.pem"`;
$server->set_config_sslport($client_path);
$server->set_config_clientssltransport('DJabberd::Connection::ClientIn');
$server->set_config_sslcertificatefile("/tmp/_test_djabberd.pem");
$server->set_config_sslcertificatekeyfile("/tmp/_test_djabberd.pem");
$server->set_config_serverport($client_port+1);
$server->set_config_clientport($client_port+2);

$server->add_vhost($vhost);

my $childpid = fork;
if (!$childpid) {
    $0 = "[djabberd]";
    $server->run;
    exit 0;
}

use IO::Socket::UNIX;
my $conn;

sub conn {
    return IO::Socket::UNIX->new(Type => SOCK_STREAM(),Peer => $sock_path);
}

foreach (1..3) {
    print "Connecting...\n";
    $conn = conn();
    last if $conn;
    sleep 1;
}

my $err = sub {
    kill 9, $childpid;
    die $_[0];
};

END {
    kill 9, $childpid;
    unlink($sock_path);
    unlink("/tmp/_test_djabberd.pem");
}

$err->("Can't connect to server") unless $conn;

my @stat = stat($sock_path) or die("cannot stat $sock_path: $@\n");
my $sg = getgrgid $stat[5] or  die("cannot find group for gid $stat[5]: $@\n");
ok($sg eq $grp, "Group $sg is properly set");
ok($stat[2] & 020, "Group is writable($stat[2])");

use Devel::Peek;

$conn->close;
for my $n (1..100) {

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

    diag("connect $n/100\n") if $n % 10 == 0;
    $conn = conn();

    print $conn qq{<?xml version='1.0'?>
        <stream:stream version='1.0'
          xmlns:stream='http://etherx.jabber.org/streams' to='jabber.example.com'
          xmlns='jabber:client'>
    };

    my $ss = $get_stream_start->();
    die unless $ss && $ss->id;

    if ($n == 100) {
        ok($ss, "got a stream back");
        ok($ss->id, "got a stream id back");
        my $el = $get_event->();
        if($el) {
	    ok($el->element_name eq 'features', "got features");
	    ok(!(grep{$_->element_name eq 'starttls'}$el->children_elements), "No SSL proposed");
	    ok((grep{$_->element_name eq 'auth'}$el->children_elements), "But has auth proposal");
        }
    }

    $p->finish_push;
    $conn->close;
}

