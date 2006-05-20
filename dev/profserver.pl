#!/usr/bin/perl
use strict;
use lib '../lib';
BEGIN {
    $ENV{LOGLEVEL} = "FATAL";
}
use DJabberd;
use DJabberd::Authen::AllowedUsers;
use DJabberd::Authen::StaticPassword;
use DJabberd::RosterStorage::SQLite;

my $roster = "prof-roster.sqlite";
unlink $roster, "$roster-journal";

my $server = DJabberd->new;
my $vhost = DJabberd::VHost->new(
                                 server_name => "example.com",
                                 s2s         => 1,
                                 plugins     => [
                                                 DJabberd::Authen::AllowedUsers->new(policy => "deny",
                                                                                     allowedusers => [qw(partya partyb)]),
                                                 DJabberd::Authen::StaticPassword->new(password => "password"),
                                                 DJabberd::RosterStorage::SQLite->new(database => $roster),
                                                 ],
                                 );

$SIG{INT} = sub {
#    $server->clean_stop;
    print "bye!\n";
    exit 0;
};

$server->add_vhost($vhost);
print "starting.\n";
$server->run;


