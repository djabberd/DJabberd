use strict;
use warnings;
use DJabberd::Caps;
use Test::More tests => 8;

# We use _complex_ show case of the XEP-0115 [5.3] to test validness
# See: http://xmpp.org/extensions/xep-0115.html##ver-gen-complex
#
#  <query xmlns='http://jabber.org/protocol/disco#info'
#         node='http://psi-im.org#q07IKJEyjvHSyhy//CH0CxmKi8w='>
#    <identity xml:lang='en' category='client' name='Psi 0.11' type='pc'/>
#    <identity xml:lang='el' category='client' name='Ψ 0.11' type='pc'/>
#    <feature var='http://jabber.org/protocol/caps'/>
#    <feature var='http://jabber.org/protocol/disco#info'/>
#    <feature var='http://jabber.org/protocol/disco#items'/>
#    <feature var='http://jabber.org/protocol/muc'/>
#    <x xmlns='jabber:x:data' type='result'>
#      <field var='FORM_TYPE' type='hidden'>
#        <value>urn:xmpp:dataforms:softwareinfo</value>
#      </field>
#      <field var='ip_version'>
#        <value>ipv4</value>
#        <value>ipv6</value>
#      </field>
#      <field var='os'>
#        <value>Mac</value>
#      </field>
#      <field var='os_version'>
#        <value>10.5.1</value>
#      </field>
#      <field var='software'>
#        <value>Psi</value>
#      </field>
#      <field var='software_version'>
#        <value>0.11</value>
#      </field>
#    </x>
#  </query>
#
my $caps = 'client/pc/el/Ψ 0.11<client/pc/en/Psi 0.11<http://jabber.org/protocol/caps<http://jabber.org/protocol/disco#info<http://jabber.org/protocol/disco#items<http://jabber.org/protocol/muc<urn:xmpp:dataforms:softwareinfo<ip_version<ipv4<ipv6<os<Mac<os_version<10.5.1<software<Psi<software_version<0.11<';
my $hash = 'q07IKJEyjvHSyhy//CH0CxmKi8w=';
my $entc = "<c xmlns='http://jabber.org/protocol/caps' hash='sha-1' node='http://psi-im.org' ver='q07IKJEyjvHSyhy//CH0CxmKi8w='/>";
my $c = DJabberd::Caps->new(
	DJabberd::Caps::Identity->new('client','pc', 'Psi 0.11', 'en'),
	DJabberd::Caps::Identity->new('client','pc', 'Ψ 0.11', 'el'),
	DJabberd::Caps::Feature->new('http://jabber.org/protocol/caps'),
	DJabberd::Caps::Feature->new('http://jabber.org/protocol/disco#info'),
	DJabberd::Caps::Feature->new('http://jabber.org/protocol/disco#items'),
	DJabberd::Caps::Feature->new('http://jabber.org/protocol/muc'),
	DJabberd::Caps::Form->new('result', [
		{ var => 'FORM_TYPE', type => 'hidden', value => [ 'urn:xmpp:dataforms:softwareinfo' ] },
		{ var => 'ip_version', value => [ 'ipv4', 'ipv6' ] },
		{ var => 'os', value => [ 'Mac' ] },
		{ var => 'os_version', value => [ '10.5.1' ] },
		{ var => 'software', value => [ 'Psi' ] },
		{ var => 'software_version', value => [ '0.11' ] }
	])
);
print "".('-'x9)."\nXML Out:\n";
print $c->as_xml;
print "\n".('-'x9)."\nCAP Out:\n";
print $c->as_cap;
print "\n".('-'x9)."\nDigest:\n";
print $c->digest;
print "\n".('-'x9)."\nEntity:\n";
print $c->cap_xml('http://psi-im.org');
print "\n".('-'x9)."\nChecks:\n";
like($c->as_xml,qr(xml:lang=["']el["']), "XML Lang attribute found");
like($c->as_xml,qr(<field var=["']FORM_TYPE["'] type=["']hidden["']>),"Form fields attributes");
ok($caps eq $c->as_cap, "Cap string matches");
ok($hash eq $c->digest, "Cap digest matches");
ok($entc eq $c->cap_xml('http://psi-im.org'), "Cap entity matches");

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
$p->parse_chunk(qq{
  <query xmlns='http://jabber.org/protocol/disco#info'
         node='http://psi-im.org#q07IKJEyjvHSyhy//CH0CxmKi8w='>
    <identity xml:lang='en' category='client' name='Psi 0.11' type='pc'/>
    <identity xml:lang='el' category='client' name='Ψ 0.11' type='pc'/>
    <feature var='http://jabber.org/protocol/caps'/>
    <feature var='http://jabber.org/protocol/disco#info'/>
    <feature var='http://jabber.org/protocol/disco#items'/>
    <feature var='http://jabber.org/protocol/muc'/>
    <x xmlns='jabber:x:data' type='result'>
      <field var='FORM_TYPE' type='hidden'>
        <value>urn:xmpp:dataforms:softwareinfo</value>
      </field>
      <field var='ip_version'>
        <value>ipv4</value>
        <value>ipv6</value>
      </field>
      <field var='os'>
        <value>Mac</value>
      </field>
      <field var='os_version'>
        <value>10.5.1</value>
      </field>
      <field var='software'>
        <value>Psi</value>
      </field>
      <field var='software_version'>
        <value>0.11</value>
      </field>
    </x>
  </query>
});
print "".('-'x9)."\nXML Original:\n";
print $q->as_xml;
print "\n".('-'x9)."\nXML Decoded:\n";
my $x = DJabberd::Caps->new($q->children_elements);
my $xml = $x->as_xml;
print $xml;
print "\n".('-'x9)."\nCap string:\n";
print $x->as_cap;
print "\n".('-'x9)."\nDigest:\n";
print $x->digest;
print "\n".('-'x9)."\nChecks:\n";
ok($x->as_cap eq $caps, "XML Transcoding check - caps export matches original caps");
ok($x->digest eq $hash, "XML Transcoding check - decoded digest matches original one");

##
# Re-parse parsed-and-exported XML again and compare hashes
my $qo = $q;
$p->parse_chunk(qq{<q xmlns='disco:info'>$xml</q>});
my $xn = DJabberd::Caps->new($q->children_elements);
print "\n".('-'x9)."\nCap string:\n";
print $xn->as_cap;
print "\n".('-'x9)."\nChecks:\n";
ok($qo != $q && $xn->digest eq $hash, "XML Transcoding check - recoded digest matches original one");

package CB;

sub new {
  my $class = shift;
  return bless { in_stream => 1, cb => $_[0] }, $class;
}
sub on_stanza_received {
    my $self = shift;
    $self->{cb}->(@_);
}
