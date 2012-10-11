#!/usr/bin/perl

use strict;
use warnings;
use XML::SAX;
use DJabberd::TestSAXHandler;
use DJabberd::XMLParser;
use XML::SAX::PurePerl;
use Scalar::Util qw(weaken);
use Test::More tests => 15;
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
    $p->parse_more("<foo>&lt;<tag>");
    $p->finish_push;
    like($dummy, qr/foo.+tag/s);
    $ref = \$p;
    weaken($ref);
}
ok(!$ref, "p went away");

## external entities are disabled
{
    use FindBin;
    my $v = "$FindBin::Bin/v.txt";

    my $xml1 = <<"EOF";
<?xml version="1.0"?>
<!DOCTYPE foo [
<!ENTITY a PUBLIC "//foo" "file:$v">
]>
<root>
  <a>&lt; A=&a;</a>
</root>
EOF
    my $xml2 = <<"EOF";
<?xml version="1.0"?>
<!DOCTYPE foo [
<!ENTITY b SYSTEM "file://$v">
]>
<root>
  <b>B=&b;</b>
</root>
EOF
    for ($xml1, $xml2) {
        my $handler = EventRecorder->new(\$dummy);
        my $p       = DJabberd::XMLParser->new(Handler => $handler);
        eval {
            $p->parse_more($_);
            $p->finish_push;
        };
        ok $@, "died on unknown entity: $@";
        unlike($dummy, qr/vuln/si);
    }
}

## regular entities in an XML document are decoded
{
    my $xml = <<"EOF";
<?xml version="1.0"?>
<root>
  <a attr="special characters are &lt; &gt; &apos; &quot; and of course &amp;" />
  <b>special characters are &lt; &gt; &apos; &quot; and of course &amp;</b>
  <c attr="special characters are &#60; &#62; &#34; &#39; and of course &#38;" />
  <d>special characters are &#60; &#62; &#34; &#39; and of course &#38;</d>
  <e attr="special characters are &#x3c; &#x3e; &#x22; &#x27; and of course &#x26;" />
  <f>special characters are &#x3c; &#x3e; &#x22; &#x27; and of course &#x26;</f>
  <g poo="&#x1f4a9;">Let's have some unicode for extra fun... &#x1f4a9;</g>
</root>
EOF

    # we process entities into &#xHEX; only
    my $expected = <<"EOF";
<root>
  <a attr='special characters are &#x3C; &#x3E; &#x27; &#x22; and of course &#x26;'/>
  <b>special characters are &#x3C; &#x3E; &#x27; &#x22; and of course &#x26;</b>
  <c attr='special characters are &#x3C; &#x3E; &#x22; &#x27; and of course &#x26;'/>
  <d>special characters are &#x3C; &#x3E; &#x22; &#x27; and of course &#x26;</d>
  <e attr='special characters are &#x3C; &#x3E; &#x22; &#x27; and of course &#x26;'/>
  <f>special characters are &#x3C; &#x3E; &#x22; &#x27; and of course &#x26;</f>
  <g poo='&#x1F4A9;'>Let&#x27;s have some unicode for extra fun... &#x1F4A9;</g>
</root>
EOF
    my $events = [];
    my $handler = DJabberd::TestSAXHandler->new($events);
    my $p = DJabberd::XMLParser->new(Handler => $handler);
    $p->parse_chunk($xml);
    my $res = $events->[0]->as_xml() . "\n";
    is($res, $expected, "parsed XML internal-entities correctly");
}

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
    my $self = $class->SUPER::new();
    $self->{outref} = $outref;
    return $self;
}

sub characters {
    my ($self, $data) = @_;
    ${ $self->{outref} } .= $data->{Data};
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

