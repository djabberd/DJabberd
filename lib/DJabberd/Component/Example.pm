
=head1 NAME

DJabberd::Component::Example - An example DJabberd service component

=head1 SYNOPSIS

  <Subdomain example>
      <Plugin DJabberd::Component::Example>
          Greeting Hello, world!
      </Plugin>
  </Subdomain>

This class implements a very simple component that responds to all incoming messages
with a predefined greeting and which returns a vCard for itself when one is requested.
You can change the greeting returned using the optional Greeting configuration setting
as above.

This example also exposes a node called "somebloke" that responds to all messages with
authentic British surprise.

This example uses the higher-level API provided by L<DJabberd::Agent|DJabberd::Agent>, from which
L<DJabberd::Component|DJabberd::Component> inherits.
L<DJabberd::Component::External|DJabberd::Component::External> serves as an example of
how to handle stanzas at a lower level by overriding the C<handle_stanza> method.

=head1 COPYRIGHT

This module is Copyright (c) 2008 Martin Atkins

This module is distributed under the same terms as the main DJabberd distribution.

=cut

package DJabberd::Component::Example;
use base DJabberd::Component;
use DJabberd::Util qw(exml);
use DJabberd::Log;
use DJabberd::JID;

our $logger = DJabberd::Log->get_logger();

sub set_config_greeting {
    my ($self, $greeting) = @_;
    
    $self->{greeting} = $greeting;
}

sub finalize {
    my ($self, $opts) = @_;
    
    $logger->info("initializing");
    $logger->info("My greeting is ", $self->{greeting});
    
    $self->{greeting} ||= "Hi! I'm an example DJabberd component!";
    $self->SUPER::finalize;
}

sub handle_message {
    my ($self, $vhost, $stanza) = @_;
    
    my $from = $stanza->from_jid;
    my $to = $stanza->to_jid;

    $logger->info("Got message from ".$from->as_string);
    
    my $response = $stanza->make_response();
    
    $response->attrs->{"{}type"} = "normal";
    $response->set_raw("<body>".exml($self->{greeting})."</body>");

    $logger->info("Responding with ".$response->as_xml);
    
    $response->deliver($vhost);

}

sub vcard {
    my ($self, $requester_jid) = @_;

    return "<FN>Example DJabberd component</FN>";
}

sub get_node {
    my ($self, $nodename) = @_;

    if ($nodename eq 'somebloke') {
        return DJabberd::Component::Example::ExampleNode->new(
            nodename => 'somebloke',
        );
    }
    else {
        return undef;
    }
}

package DJabberd::Component::Example::ExampleNode;

use base DJabberd::Agent::Node;
use DJabberd::Util qw(exml);

sub handle_message {
    my ($self, $vhost, $stanza) = @_;
    
    $logger->info("It's a message to some bloke.");

    my $responsetext = "Gaw blimey, guvna!";

    my $response = $stanza->make_response();
    $response->set_raw("<body>".exml($responsetext)."</body>");
    $response->deliver($vhost);
}

sub vcard {
    return "<FN>Some Bloke</FN>";
}

1;
