#!/usr/bin/perl

use strict;
use Test::More 'no_plan';
use DJabberd::StreamVersion;

my $ver;

$ver = DJabberd::StreamVersion->new("1.0");
ok($ver, "got obj");
ok($ver->valid);

my $ver12 = DJabberd::StreamVersion->new("1.2");
my $ver21 = DJabberd::StreamVersion->new("2.1");

is($ver12->min($ver)->as_string, "1.0");

is($ver12->cmp($ver), 1, "1.2 is greater");
is($ver->cmp($ver12), -1, "1.0 is less");

is($ver21->cmp($ver12), 1, "2.1 is greater");
is($ver12->cmp($ver21), -1, "1.2 is less");

ok($ver12->supports_features);

my $veremp = DJabberd::StreamVersion->new("");
ok(! $veremp->valid, "empty not valid");

my $ver09 = DJabberd::StreamVersion->new("0.9");
ok(! $ver09->supports_features, "0.9 no features");

