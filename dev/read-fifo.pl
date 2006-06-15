#!/usr/bin/perl
use strict;
my $fifo = shift;
unless (-p $fifo) {
    die "That isn't a FIFO.\n";
}

while (1) {
    my @queue;
    my $queue_max = 50_000;

    open(my $fh, $fifo) or die "Failed to open FIFO: $!";
    while (<$fh>) {
        push @queue, $_;
        shift @queue if @queue > $queue_max;
    }

    my $time = time();
    open(my $writer, ">close-at-$time.trace");
    print $writer $_ foreach @queue;
}

