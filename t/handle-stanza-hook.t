#!/usr/bin/perl
use strict;
use Test::More tests => 3;
use lib 't/lib';
require 'djabberd-test.pl';

{
  # Example plugin that uses the HandleStanza hook
  # responds to <foo/> stanzas with <bar/>
  package FooStanza;
    use base qw(DJabberd::Stanza);
    
    sub register {
      my ($self, $vhost) = @_;
      $vhost->register_hook("HandleStanza", sub { $self->handle_stanza(@_) });
    }
    
    sub handle_stanza {
      my ($self, $vhost, $cb, $node, $stanza) = @_;
      if($node->element eq "{jabber:client}foo") {
        return $cb->handle("FooStanza");    
      }
      return $cb->decline;
    }

    sub on_recv_from_client {
        my ($self, $conn) = @_;        
        $conn->write("<bar/>");
        
        # ALERT! big hack
        # Brad doesn't like noisy tests... and this test tests a condition that's supposed to log a warning
        # specifically,  it's supposed to test that the server returns unsupported-stanza-type
        # in response to stanzas that it doesn't recognize
        # So I've basically clobbered the connection logger, so that this is not output during test run
        # If you really want to see this stuff you probably would have set LOGLEVEL=DEBUG
        # And so in that case we will avoid clobbering the logger
        if($ENV{LOGLEVEL} eq "WARN"){
          $conn->{log} = DJabberd::Log->get_logger("Nothing");
        }
    }
}

#Create a server with the standard plugin, plus the FooStanza plugin
my $server = Test::DJabberd::Server->new(id => 1);
$server->start([
    FooStanza->new(), 
    DJabberd::Authen::AllowedUsers->new(policy => "deny",allowedusers => [qw(partya partyb)]),
    DJabberd::Authen::StaticPassword->new(password => "password"),
    DJabberd::RosterStorage::InMemoryOnly->new(),
    DJabberd::Delivery::Local->new,
    DJabberd::Delivery::S2S->new]);

my $client = Test::DJabberd::Client->new(server => $server, name => "client");

{
    $client->login;
    $client->send_xml("<presence/>");
    
    select(undef, undef, undef, 0.25);
    
    # when sending foo stanza
    $client->send_xml(qq{<foo/>});
    # should get bar stanza
    is($client->recv_xml, 
        "<bar/>",
        "should get a bar stanza in response to foo stanza");    
    
    # when sending bogus stanza
    $client->send_xml(qq{<bogus-stanza/>});
    # should get a stream error
    is($client->recv_xml, 
        "<error xmlns='http://etherx.jabber.org/streams'><unsupported-stanza-type xmlns='urn:ietf:params:xml:ns:xmpp-streams'/></error>",
        "should get a stream error for bogus stanza");
    
    pass "Done";
}
