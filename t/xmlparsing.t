#!/usr/bin/perl

use strict;
use warnings;
use XML::SAX;
use DJabberd::XMLParser;
use XML::SAX::PurePerl;
use Scalar::Util qw(weaken);
use Test::More tests => 10;
use Data::Dumper;

my $fulldoc = qq{<?xml version="1.0"?><root xmlns='root' xmlns:a='aa' global='foo' xmlns:b='bb' a:name='aname' b:name='bname' name='globalname'>
  <a:tag />
  <b:tag />
  <tag />
  </root>};

my $correct;
{
    my $p = XML::SAX::PurePerl->new(Handler => EventRecorder->new(\$correct));
    $p->parse_string($fulldoc);
}
like($correct, qr/bname/);
like($correct, qr/aname/);
like($correct, qr/globalname/);
like($correct, qr/root/);
like($correct, qr/tag/);


my $dummy;
my $ref;

{
    my $handler = EventRecorder->new(\$dummy);
    my $p       = DJabberd::XMLParser->new(Handler => $handler);
    $p->finish_push;
    ok(!$dummy);
    $ref = \$p;
    weaken($ref);
}
ok(!$ref, "p went away");

{
    my $handler = EventRecorder->new(\$dummy);
    my $p       = DJabberd::XMLParser->new(Handler => $handler);
    $p->parse_more("<foo><tag>");
    $p->finish_push;
    like($dummy, qr/foo.+tag/s);
    $ref = \$p;
    weaken($ref);
}
ok(!$ref, "p went away");

# byte at a time
my $n = 0;
my $byte_events;
while ($n < ($ENV{BYTE_RUNS} || 1)) {
    $n++;
    if ($n % 10 == 0) {
        warn "$n\n";
    }

    {
        my $handler = EventRecorder->new(\$byte_events);
        my $p       = DJabberd::XMLParser->new(Handler => $handler);
        foreach my $byte (split(//, $fulldoc)) {
            $p->parse_chunk_scalarref(\$byte);
        }
        $p->finish_push;  # cleanup
    }
}
ok($byte_events eq $correct, "djabberd parser gets same results");


package EventRecorder;
use strict;
use base qw(XML::SAX::Base);
use Data::Dumper;

sub new {
    my ($class, $outref) = @_;
    $$outref = "";
    return bless {
        outref => $outref,
    };
}

sub start_element {
    my ($self, $data) = @_;
    $Data::Dumper::Sortkeys = 1;
    $Data::Dumper::Indent = 1;
    ${ $self->{outref} } .= "START: " . Dumper($data);
}

sub end_element {
    my ($self, $data) = @_;
    $Data::Dumper::Sortkeys = 1;
    $Data::Dumper::Indent = 1;
    ${ $self->{outref} } .= "END: " . Dumper($data);
}

1;

