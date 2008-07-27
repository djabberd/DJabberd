#!/usr/bin/perl
use strict;
use Test::More 'no_plan';
use lib 't/lib';
use File::Find;

my $Dir = 't/log';
{   $ENV{XMLDEBUG}  = $Dir;
    mkdir $Dir unless -d $Dir;
}

require 'djabberd-test.pl';

my $server = Test::DJabberd::Server->new(id => 1);
ok( $server,                    "Have a server" ),
ok( $server->start,             "   Server started" );

my $pid = $server->{pid};
ok( $pid,                       "   On $pid" );
ok( not( -d "$Dir/$pid" ),      "   No logging yet" );

my $pa = Test::DJabberd::Client->new(
            server => $server, name => "partya" );
ok( $pa,                        "Client created" );
ok( $pa->login,                 "   Logged in" );

ok( -d "$Dir/$pid",             "Log directory now exists" );

my @files = glob( "$Dir/$pid/*" );
is( scalar(@files), 1,          "   Found one log file: @files" );

my $contents = do { 
    open my $fh, $files[0] or warn $!; local $/; <$fh>; 
};

diag( $contents ) if $ENV{TESTDEBUG};
ok( $contents,                  "   It has content" );
like( $contents, qr/<.+>/,      "       Which looks like XML" );
