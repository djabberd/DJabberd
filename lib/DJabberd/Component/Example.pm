
=head1 NAME

DJabberd::Component::Example - An example DJabberd service component

=head1 SYNOPSIS

  <Plugin DJabberd::Plugin::Component>
     Subdomain example
     Class DJabberd::Component::Example
     Greeting Hello, world!
  </Plugin>

This class implements a very simple component that responds to all incoming messages
with a predefined greeting and which returns a vCard for itself when one is requested.
You can change the greeting returned using the optional Greeting configuration setting
as above.

This example also exposes a node called "eliza" that allows you to talk to an Eliza chatbot.

=cut

package DJabberd::Component::Example;
use base DJabberd::Component;
use DJabberd::Util qw(exml);
use DJabberd::Log;
use DJabberd::Bot::Eliza;
use DJabberd::JID;

our $logger = DJabberd::Log->get_logger();

sub initialize {
    my ($self, $opts) = @_;
    
    $self->{greeting} = $opts->{greeting} || "Hi! I'm an example DJabberd component!";
    $self->{eliza} = new DJabberd::Bot::Eliza();
}

sub handle_stanza {
    my ($self, $vhost, $cb, $stanza) = @_;

    $logger->info("Got stanza: ".$stanza->as_summary);

    my $from = $stanza->from_jid;
    my $to = $stanza->to_jid;

    # Expose an Eliza bot on node "eliza"
    if ($to->node eq 'eliza' || $to->node eq '3l1z4') {
    
        if ($stanza->isa('DJabberd::Message')) {

            $logger->info("It's a message to our Eliza bot.");

            my $responsetext = $self->{eliza}->handle_message($stanza);

            if ($responsetext) {
                
                if ($to->node eq '3l1z4') {
                    # l33t eliza
                    $responsetext = uc($responsetext);
                    $responsetext =~ s/CK/X/g;
                    $responsetext =~ s/ER(\b)/0R$1/g;
                    $responsetext =~ tr/AIETO/41370/;
                    $responsetext =~ s/X/></;
                    $responsetext =~ s/([A-Z])/ ( rand(1) > 0.6 ? lc($1) : $1 ) /eg;
                }
            
                my $response = $self->_make_response($stanza);
                $response->set_raw("<body>".exml($responsetext)."</body>");
                $response->deliver($vhost);
            }

        }
        elsif ($stanza->isa('DJabberd::IQ') && $stanza->signature eq 'get-{vcard-temp}vCard') {
        
            $logger->info("It's a vCard request for our Eliza bot.");
        
            my $response = $self->_make_response($stanza);
            $response->attrs->{"{}type"} = "result";
            $response->set_raw("<vCard xmlns='vcard-temp'><FN>Example Eliza Bot</FN></vCard>");
            $logger->info("Responding with ".$response->as_xml);
            $response->deliver($vhost);
        }

        $cb->delivered;
        return;
    }

    # Other than for Eliza, we only want stanzas addressed to the domain, since there
    # aren't any other nodes under this component.
    if ($to->as_string ne $self->domain) {
        $logger->info("Message to ".$stanza->to_jid->as_string.", not ".$self->domain.". Discarding.");
        $cb->decline;
        return;
    }

    if ($stanza->isa('DJabberd::IQ')) {
    
        if ($stanza->signature eq 'get-{vcard-temp}vCard') {
        
            $logger->info("Got vCard request from ".$stanza->from_jid->as_string);

            my $response = $self->_make_response($stanza);
            $response->attrs->{"{}type"} = "result";
            $response->set_raw("<vCard xmlns='vcard-temp'><FN>Example DJabberd component</FN></vCard>");
            $logger->info("Responding with ".$response->as_xml);
            $response->deliver($vhost);

            $cb->delivered;
            return;
        
        }
        else {
            $logger->info("Got unrecognized IQ stanza from ".$stanza->from_jid->as_string);
            $cb->decline;
            return;
        }
    }
    elsif ($stanza->isa('DJabberd::Message')) {
        
        $logger->info("Got message from ".$from->as_string);
        
        my $response = $self->_make_response($stanza);
        
        $response->attrs->{"{}type"} = "normal";
        $response->set_raw("<body>".exml($self->{greeting})."</body>");

        $logger->info("Responding with ".$response->as_xml);
        
        $response->deliver($vhost);
        
        $cb->delivered;
        return;
    }
    
    $logger->info("I don't know what to do with $stanza");
    $cb->decline;
}


sub _make_response {
    my ($self, $stanza) = @_;

    my $response = $stanza->clone;
    my $from = $stanza->from;
    my $to   = $stanza->to;

    $response->set_to($from);
    $to ? $response->set_from($to) : delete($response->attrs->{"{}from"});

    return $response;
}


1;
