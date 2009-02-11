#!/usr/bin/perl
use strict;
use Test::More tests => 11;
use lib 't/lib';
require 'djabberd-test.pl';

my $HAS_SASL;
eval "use Authen::SASL 2.13";
$HAS_SASL = 1 unless $@;

sub connect_and_get_features{
   my $client = shift;
   my $sock;
   my $addr;
   if ($addr = $client->{unixdomainsocket}) {
       $sock = IO::Socket::UNIX->new(Peer => $addr);
   } else {
       $addr = join(':',
                    $client->server->peeraddr,
                    $client->server->clientport);
       for (1..3) {
           $sock = IO::Socket::INET->new(PeerAddr => $addr,
                                         Timeout => 1);
           last if $sock;
           sleep 1;
       }
   }

   $client->{sock} = $sock
       or die "Cannot connect to server " . $client->server->id . " ($addr)";

   my $to = $client->server->hostname;

   print $sock "
  <stream:stream
      xmlns:stream='http://etherx.jabber.org/streams'
      xmlns='jabber:client' to='$to' version='1.0'>";

   $client->{ss} = $client->get_stream_start();

   my $features = $client->recv_xml;
  
  return $features
}

#Create a basic server, should only have only auth feature
{
  my $server = Test::DJabberd::Server->new(id => 1);
  $server->start( $server->std_plugins_sans_sasl );
  my $client = Test::DJabberd::Client->new(server => $server, name => "client");
  {
     my $features = connect_and_get_features($client);

     is("<features xmlns='http://etherx.jabber.org/streams'><auth xmlns='http://jabber.org/features/iq-auth'/></features>",
        $features, "should get features, including auth and nothing else");
  }
  $server->kill;  

  SKIP: {
    skip "These tests require SASL", 8 unless $HAS_SASL;
    $server = Test::DJabberd::Server->new(id => 1);
    $server->start( ); # by default we have SASL plugin enabled
    my $client = Test::DJabberd::Client->new(server => $server, name => "client");
    {
        my $features = connect_and_get_features($client);

        like($features, qr{^<features xmlns='http://etherx.jabber.org/streams'>.*</features>$});
        like($features, qr{<auth xmlns='http://jabber.org/features/iq-auth'/>});
        like($features, qr{<mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>.*</mechanisms>});
        like($features, qr{<optional/>}, "our test setup makes sasl optional, bc of history of djabberd");
        for my $mech (qw/PLAIN DIGEST-MD5 LOGIN/) {
            like($features, qr{<mechanism>$mech</mechanism>}, "supports $mech");
        } 

        like($features, qr{<mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>.*</mechanisms>});
    }
    $server->kill;  
  };
}


#Create a server with ssl, features should have auth and starttls
{
  my $server = Test::DJabberd::Server->new(id => 1);
  $server->start([DJabberd::Authen::AllowedUsers->new(policy => "deny",allowedusers => [qw(partya partyb)]),
      DJabberd::Authen::StaticPassword->new(password => "password"),
      DJabberd::RosterStorage::InMemoryOnly->new(),
      DJabberd::Delivery::Local->new,
      DJabberd::Delivery::S2S->new],
      sub {
        my $srv = shift;
        #This hack convinces vhost that ssl is enabled enough to send starttls...
        $srv->{ssl_cert_file} = "features-hook.t";
      }
      );
  my $client = Test::DJabberd::Client->new(server => $server, name => "client");
  {
     my $features = connect_and_get_features($client);

     is("<features xmlns='http://etherx.jabber.org/streams'>".
        "<auth xmlns='http://jabber.org/features/iq-auth'/>".
        "<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>".
        "</features>",
        $features, "should get features, including auth and starttls");
  }
  $server->kill;  
}

{
  package FooBarPlugin;
    sub new {
      my ($class) = @_;
      my $self = bless {}, $class;
      return $self;
    }
    sub register {
      my ($self, $vhost) = @_;
      $vhost->register_hook("SendFeatures", sub { 
        my ($vhost, $cb, $conn) = @_;
        return $cb->stanza("<foobar/>");        
      });
    }
}

#Create a server with FooBarPlugin, features should have auth and foobar
{
  my $server = Test::DJabberd::Server->new(id => 1);
  $server->start([
      FooBarPlugin->new,
      DJabberd::Authen::AllowedUsers->new(policy => "deny",allowedusers => [qw(partya partyb)]),
      DJabberd::Authen::StaticPassword->new(password => "password"),
      DJabberd::RosterStorage::InMemoryOnly->new(),
      DJabberd::Delivery::Local->new,
      DJabberd::Delivery::S2S->new]);
  my $client = Test::DJabberd::Client->new(server => $server, name => "client");
  {
     my $features = connect_and_get_features($client);

     is("<features xmlns='http://etherx.jabber.org/streams'>".
        "<auth xmlns='http://jabber.org/features/iq-auth'/>".
        "<foobar/>".
        "</features>",
        $features, "should get features, including auth and starttls");
  }
  $server->kill;  
}


