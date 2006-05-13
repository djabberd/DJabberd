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
use Test::More tests => 11;
use Data::Dumper;

my $mode = shift;

my $factory = XML::SAX::ParserFactory->new;
my $wanted = ""; # set to nothing to let the factory choose a parser
my $iter_method;

if ($mode eq "") {
    # automatic, let SAX do it.
} elsif ($mode eq "libxml") {
    $wanted = "XML::LibXML::SAX";
    $iter_method = "parse_chunk";
} elsif ($mode eq "libxml-better") {
    $wanted = "XML::LibXML::SAX::Better";
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
    $p->$iter_method($first_chunk);
    $p->$iter_method($second_chunk);
    $weakcheck = \$p;
    weaken($weakcheck);

}
is($weakcheck, undef, "parser was destroyed");

use Text::Diff;
my $diff = diff(\$full_events, \$streamed_events);
#$diff = substr($diff, 0, 200);
is($diff, "", "events match either way");

# byte at a time
my $n = 0;
my $byte_events;
while (1) {
    $n++;
    if ($n % 1000 == 0) {
        print "$n\n";
    }

    {
        my $handler = EventRecorder->new(\$byte_events);
        my $p       = $factory->parser(Handler => $handler);
        foreach my $byte (split(//, $fulldoc)) {
            $p->$iter_method($byte);
        }
    }
}

$diff = diff(\$full_events, \$byte_events);
is($diff, "", "events match doing it byte-at-a-time");

print $byte_events;

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

package XML::LibXML::SAX::Better;
use strict;
use vars qw($VERSION @ISA);
$VERSION = '1.00';
use XML::LibXML;
use XML::SAX::Base;
use base qw(XML::SAX::Base);
use Carp;
use Data::Dumper;

sub new {
    my ($class, @params) = @_;
    my $inst = $class->SUPER::new(@params);

    my $libxml = XML::LibXML->new;
    $libxml->set_handler( $inst );
    $inst->{LibParser} = $libxml;

    # setup SAX.  1 means "with SAX"
    $libxml->_start_push(1);
    $libxml->init_push;

    return $inst;
}

sub parse_chunk {
    my ( $self, $chunk ) = @_;
    my $libxml = $self->{LibParser};
    my $rv = $libxml->push($chunk);
}


# compat for test:

sub _parse_string {
    my ( $self, $string ) = @_;
#    $self->{ParserOptions}{LibParser}      = XML::LibXML->new;
    $self->{ParserOptions}{LibParser}      = XML::LibXML->new()     unless defined $self->{ParserOptions}{LibParser};
    $self->{ParserOptions}{ParseFunc}      = \&XML::LibXML::parse_string;
    $self->{ParserOptions}{ParseFuncParam} = $string;
    return $self->_parse;
}

sub _parse {
    my $self = shift;
    my $args = bless $self->{ParserOptions}, ref($self);

    $args->{LibParser}->set_handler( $self );
    $args->{ParseFunc}->($args->{LibParser}, $args->{ParseFuncParam});

    if ( $args->{LibParser}->{SAX}->{State} == 1 ) {
        croak( "SAX Exception not implemented, yet; Data ended before document ended\n" );
    }

    return $self->end_document({});
}


1;

