#!/usr/bin/perl

use strict;
my $mode = shift;
die "invalid mode, not on or off" unless $mode =~ /^on|off$/;

my @files = grep { $_ !~ m!/\.svn/! } `find lib -name '*.pm'`;
chomp @files;

foreach my $f (@files) {
    print " * $_\n" foreach @files;
    open (my $fh, $f) or die;
    my $data = "";
    my $linenum = 0;
    while (my $line = <$fh>) {
        $linenum++;
        if ($mode eq "on") {
            $line =~ s/\bsub\s*\{/DJabberd::Util::lbsub sub \{/g;
        } else {
            $line =~ s/DJabberd::Util::lbsub sub \{/sub \{/g;
        }
        $data .= $line;
    }
    close ($fh);
    open (my $fh, ">$f") or die;
    print $fh $data;
    close $fh;
}




