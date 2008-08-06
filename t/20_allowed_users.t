#!/usr/bin/perl
use strict;
use lib         't/lib';
use Test::More  'no_plan';

#BEGIN { $ENV{LOGLEVEL}  = 'DEBUG' };

require 'djabberd-test.pl';

use Data::Dumper;
$Data::Dumper::Indent = 1;

### start server with standard plugins
my $server = Test::DJabberd::Server->new( id => 1 );

ok( $server,                    "Server object created" );
ok( $server->start,             "   Server started" );


### standard users allowed users are 'partya' and 'partyb', log them in:
### then try to log in a user that shouldn't be allowed to log in
### 
### This checks for an issue where AllowedUsers->check_cleartext never gets
### called, and anyone can just log in
for my $aref( [partya => 1], [partyb => 1], ["foo$$" => 0] ) {
    my($user, $ok_login) = @$aref;

    my $client = Test::DJabberd::Client->new(server => $server, name => $user);
    ok( $client,                "$user object created" );

    ### for the todo test, see this mail to the mailinglist:
    ### http://lists.danga.com/pipermail/djabberd/2008-August/000623.html
    my $rv = $client->login;
    $ok_login
        ? ok( $rv,              "   $user logged in" )
        : do {  local $TODO = "::StaticPassword interfers with ::AllowedUsers"; 
                ok( !$rv,             "   $user log in denied" );
            };            
}
