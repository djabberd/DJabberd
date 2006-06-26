#!/usr/bin/perl

use strict;
use Test::More;
use FindBin qw($Bin);

plan skip_all => 'Not yet working';

my $lib = "$Bin/../lib";
my $docs = "$Bin/../doc/";

opendir(my $d, $docs) or die;
my @docs = sort grep { /-notes\.txt$/ } readdir($d);
close $d;

my %point;    # key -> { where => , impl => $bool }
my @points;   # keys

foreach my $f (@docs) {
    my $pretty_file = $f;
    if ($f =~ /^rfc(\d+)/) {
        $pretty_file = "rfc$1";
    }

    my ($sec, $subsec, $subsecnum, $lineno);

    open (my $fh, "$docs/$f") or die $!;
    while (my $line = <$fh>) {
        $lineno++;

        # look for section/subsection headings
        if ($line =~ /^\d+\.\s+(.+)/) {
            $sec = $1;
            $subsec = "";
            $subsecnum = 0;
            next;
        }

        if ($line =~ /^(\d+\.\d+)\.\s+(.+)/) {
            $subsec = $2;
            $subsecnum = $1;
            next;
        }

        while ($line =~ s/\{=(.+?)\}//) {
            my $key = $1;
            my $where = "$subsecnum: $sec >> $subsec ($pretty_file, line $lineno)";
            die "Point $key already seen" if $point{$key};
            $point{$key} = { where => $where };
            push @points, $key;
        }
    }
}

chomp(my @pm_files = `find $lib -name '*.pm'`);
foreach my $key (implemented_points_in_files(@pm_files)) {
    $point{$key}->{impl} = 1;
}

foreach my $p (@points) {
    my $pt = $point{$p};
    ok($pt->{impl}, "$p: $pt->{where}");
#    print "Point:  $p  = $pt->{where}, $pt->{impl}\n";
}



sub implemented_points_in_files {
    my (@files) = @_;
    return map { implemented_points_in_file($_) } @files;
}

sub implemented_points_in_file {
    my $f = shift;
    open(my $fh, $f) or die;
    my @seen;
    while (<$fh>) {
        while (s/\{=(.+?)\}//) {
            push @seen, $1;
        }
    }
    return @seen;
}

