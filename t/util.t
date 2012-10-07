#!/usr/bin/perl
use strict;
use warnings;

use DJabberd::Util qw(exml tsub lbsub as_bool as_num as_abs_path as_bind_addr);
use Test::More qw(no_plan);

#
# Test as_bool
#
foreach my $val (qw(1 y yes true t on enabled)) {
    eval {
        ok(as_bool($val),$val.' is true');
    };
}
foreach my $val (qw(0 n no false f off disabled)) {
    eval {
        is(as_bool($val),0,$val.' is false');
    };
}
foreach my $val (undef, 'A') {
    no warnings;
    my $eval_status = eval {
        if(defined(as_bool($val))) {
            return 0;
        } else {
            return 1;
        }
    };
    ok(defined($@),$val.' is not of type bool');
    ok(!defined($eval_status),$val.' is not of type bool');
}

#
# Test as_num
#
foreach my $val (qw(0 1 1000 65534)) {
    eval {
        is(as_num($val),$val,$val.' is a valid num');
    };
}
# invalid values
{
    no warnings;
    foreach my $val (qw(0.0 1.2 3,5 2001:db8:: abc 100000 127.0.0.1:0 127.0.0.1:65536),undef) {
        my $eval_status = eval {
            as_bind_addr($val);
        };
        ok(defined($@),$val.' is not a valid num');
        ok(!defined($eval_status),$val.' is not a valid num');
    }
}
#
# Test as_bind_addr
#
# valid values
foreach my $val (qw(12345 127.0.0.1:12345 [2001:db8::1]:12345 /tmp /tmp/)) {
    eval {
        ok(as_bind_addr($val),$val.' is a valid bind addr');
    };
}
# invalid values
foreach my $val (qw(123456 2001:db8:: 2001:db8::12345 tmp/)) {
    my $eval_status = eval {
        as_bind_addr($val);
    };
    ok(defined($@),$val.' is not a valid bind addr');
    ok(!defined($eval_status),$val.' is not a valid bind addr');
}
