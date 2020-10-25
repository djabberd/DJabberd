use strict;
use warnings;
use Test::More tests => 7;

use_ok('DJabberd::Form','Use');

#######################
#  XML Parsing check  #
#######################
use DJabberd::SAXHandler;
use DJabberd::XMLParser;
use DJabberd::Stats;
my $q = {};
my $cb = CB->new(sub {
	$q = shift;
});

my $h=DJabberd::SAXHandler->new;
my $p=DJabberd::XMLParser->new(Handler => $h);
$p->parse_chunk("<stream:stream xmlns:stream='jabber:client'>");
$h->set_connection($cb);
$p->parse_chunk(q{
<iq id='y4_962_BKTOC' from='pushy@example.org/8e8488dd69c7b163c5' type='set'>
	<enable node='jMSTc70SS4eU' jid='p2.example.eu' xmlns='urn:xmpp:push:0'>
		<x type='submit' xmlns='jabber:x:data'>
			<field var='FORM_TYPE' type='hidden'><value>http://jabber.org/protocol/pubsub#publish-options</value></field>
			<field var='secret'><value>vfSWZ0sHFL3/4TVBg+eogXX1</value></field>
		</x>
	</enable>
</iq>
});
print "".('-'x9)."\nXML Original:\n";
print $q->as_xml;
print "\n".('-'x9)."\nXML Decoded:\n";
my $x = DJabberd::Form->new($q->first_element->first_element);
my $xml = $x->as_xml;
print $xml;
print "\n".('-'x9)."\nForm Type:\n";
print $x->form_type;
print "\n".('-'x9)."\nChecks:\n";
# deserialisation checks
ok($x->type eq 'submit', "Form type");
ok($x->form_type eq 'http://jabber.org/protocol/pubsub#publish-options', "Form FORM_TYPE");
my @v = $x->value('secret');
ok($v[0] eq 'vfSWZ0sHFL3/4TVBg+eogXX1', 'Form content');
# Serialisation check
like($xml, qr{<x\s+.*type=["']submit['"].*?>}, "Has Form Type");
like($xml, qr{<field\s+.*var=['"]FORM_TYPE['"].*?><value>http://jabber.org/protocol/pubsub#publish-options</value></field>}, "Has FORM_TYPE");
like($xml, qr{<field\s+var=['"]secret['"]><value>vfSWZ0sHFL3/4TVBg\+eogXX1</value></field>},"Has Form Data");

package CB;

sub new {
  my $class = shift;
  return bless { in_stream => 1, cb => $_[0] }, $class;
}
sub on_stanza_received {
    my $self = shift;
    $self->{cb}->(@_);
}
