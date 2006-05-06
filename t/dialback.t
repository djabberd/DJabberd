#!/usr/bin/perl

use strict;
use lib 'lib';
use DJabberd;
use DJabberd::Authen::AllowedUsers;
use DJabberd::Authen::StaticPassword;
use DJabberd::TestSAXHandler;
use DJabberd::RosterStorage::SQLite;
use DJabberd::RosterStorage::Dummy;
use DJabberd::RosterStorage::LiveJournal;

use FindBin qw($Bin);

my $roster = "$Bin/test-roster.dat";
unlink($roster);

my $vhost = DJabberd::VHost->new(
                                 server_name => 'jabber.bradfitz.com',
                                 s2s         => 1,
                                 plugins   => [
                                               DJabberd::Authen::AllowedUsers->new(policy => "deny",
                                                                                   allowed => [qw(tester)]),
                                               DJabberd::Authen::StaticPassword->new(password => "password"),
                                               DJabberd::PresenceChecker::Local->new(),
                                               DJabberd::Delivery::Local->new(),
                                               DJabberd::Delivery::S2S->new(),
                                               DJabberd::RosterStorage::SQLite->new($roster),
                                               ],
                                 );

my $server = DJabberd->new;

my $childpid = fork;
if (!$childpid) {
    $server->run;
    exit 0;
}

$SIG{INT} = sub { kill 9, $childpid; exit 0; };

use IO::Socket::INET;
my $conn;

foreach (1..3) {
    print "Connecting...\n";
    $conn = IO::Socket::INET->new(PeerAddr => "127.0.0.1:5269", Timeout => 1);
    last if $conn;
    sleep 1;
}

my $err = sub {
    kill 9, $childpid;
    die $_[0];
};

$err->("Can't connect to server") unless $conn;

my @events;
my $handler = DJabberd::TestSAXHandler->new(\@events);
my $p = XML::SAX::Expat::Incremental->new( Handler => $handler );

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

# TODO: test opening stream with bogus crap
# TODO: test capturing going out of control, sending crap forever, filling memory

print $conn "
   <stream:stream
       xmlns:stream='http://etherx.jabber.org/streams'
       xmlns='jabber:server'
       xmlns:db='jabber:server:dialback'>
";

my $ss = $get_stream_start->();
print "got a streamstart: $ss\n";

use Data::Dumper;
warn Dumper($ss);

while (my $ev = $get_event->()) {
    print "GOT event: $ev\n";
}

