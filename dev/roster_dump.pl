#!/usr/bin/perl

use DBI;
use strict;
use Data::Dumper;
use warnings;
use DJabberd::Subscription;
my $file = shift;
my $username = shift;
my $dbh = DBI->connect("dbi:SQLite:dbname=$file","","", { RaiseError => 1, PrintError => 0, AutoCommit => 1 });

my $user = $dbh->selectrow_hashref("SELECT jidid FROM jidmap WHERE jid = ?", undef, $username);
my $rows = $dbh->selectall_hashref("SELECT jidmap.jid, roster.name, roster.subscription FROM roster,jidmap "
                                  . "WHERE roster.userid = ? AND jidmap.jidid = roster.contactid",
                                  "jid", undef, $user->{jidid});



my ($jid, $pendout, $to, $pendin, $from);
format STDOUT_TOP =
JID                                         pendout    to    pendin    from
------------------------------------------------------------------------------
.


    format STDOUT =
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  | @||||||| | @|| | @|||||| | @|||| |
$jid,$pendout,$to,$pendin,$from
.
#print "JID\tpendout\tout\tpendin\tin\n";

foreach my $row (values %$rows) {
    my $subscription = DJabberd::Subscription->from_bitmask($row->{subscription});
    $jid = $row->{jid};
    $pendout = $subscription->{pendout} ? "pendout" : "";
    $to      = $subscription->{to}      ? "to"      : "";
    $pendin  = $subscription->{pendin}  ? "pendin"  : "";
    $from    = $subscription->{from}    ? "from"    : "";
    write();
}


print "------------------------------------------------------------------------------\n";


