#!/usr/bin/perl
#
# usage:
#   xml-test.pl         (automatic mode)
#   xml-test.pl libxml
#   xml-test.pl expat

use strict;
use warnings;
use XML::SAX;
use XML::SAX::ParserFactory;
use Scalar::Util qw(weaken);
use Test::More tests => 5;

my $mode = shift;

my $factory = XML::SAX::ParserFactory->new;
my $wanted = ""; # set to nothing to let the factory choose a parser
my $iter_method;

if ($mode eq "") {
    # automatic, let SAX do it.
} elsif ($mode eq "libxml") {
    $wanted = "XML::LibXML::SAX";
    $iter_method = "parse_chunk";
} elsif ($mode eq "expat") {
    $wanted = "XML::SAX::Expat::Incremental";
    $iter_method = "parse_more";
}

$XML::SAX::ParserPackage = $wanted if $wanted;
$factory->require_feature('http://xml.org/sax/features/namespaces');

my $fulldoc = qq{<root xmlns='root' xmlns:a='aa' global='foo' xmlns:b='bb' a:name='aname' b:name='bname' name='globalname'>
  <a:tag />
  <b:tag />
  <tag />
  </root>};

my $first_chunk  = substr($fulldoc, 0, 50);
my $second_chunk = substr($fulldoc, 50, length($fulldoc) - 50);
is($fulldoc, $first_chunk . $second_chunk, "got doc in two chunks");

# first we do the traditional way:  "here's the whole document!"
my $full_events;
my $weakcheck;
my $weakcheck_h;
{
    my $handler = EventRecorder->new(\$full_events);
    my $p       = $factory->parser(Handler => $handler);
    if ($wanted) {
        isa_ok($p, $wanted);
    } else {
        ok(1);
    }
    $p->parse_string($fulldoc);
    $weakcheck = \$p;
    weaken($weakcheck);
    $weakcheck_h = \$handler;
    weaken($weakcheck_h);

    like($full_events, qr/\{aa\}name/, "parser supports namespaces properly");
    like($full_events, qr/\{bb\}name/, "parser supports namespaces properly");
    like($full_events, qr/\{\}global/, "parser supports namespaces properly");
}
is($weakcheck, undef, "parser was destroyed");
is($weakcheck_h, undef, "handler was destroyed");

# now we do the way we want, sending chunks:
my $streamed_events;
{
    my $handler = EventRecorder->new(\$streamed_events);
    my $p       = $factory->parser(Handler => $handler);
    # XXX FIXME: what do we put in here?
    eval {
        $p->$iter_method($first_chunk);
        $p->$iter_method($second_chunk);
    };
    $weakcheck = \$p;
    weaken($weakcheck);

}
is($weakcheck, undef, "parser was destroyed");

use Text::Diff;
my $diff = diff(\$streamed_events, \$full_events);
is($diff, "", "events match either way");

#$p->parse_done;
ok(1);

package EventRecorder;
use strict;
use base qw(XML::SAX::Base);
use Data::Dumper;

sub new {
    my ($class, $outref) = @_;
    return bless {
        outref => $outref,
    };
}

sub start_element {
    my ($self, $data) = @_;
    ${ $self->{outref} } .= Dumper($data);
}
