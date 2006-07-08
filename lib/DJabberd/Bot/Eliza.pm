
=head1 NAME

DJabberd::Bot::Eliza - An Eliza chatbot for DJabberd

=head1 SYNOPSIS

  <Plugin DJabberd::Plugin::Bot>
     Nodename eliza
     Class DJabberd::Bot::Eliza
     Chatname Eliza
  </Plugin>
  
or

  my $eliza = DJabberd::Bot::Eliza->new($jid, { chatname => 'Eliza' });
  my $response_text = $eliza->handle_message($message_stanza);

This class is a DJabberd chatbot using the well-known Eliza algorithm.
It is supplied as an example of how to write and use a bot for DJabberd.

The optional Chatname parameter specifies what the bot will call itself in
chat messages. It defaults to being the same as the Nodename.

This class requires the CPAN module Chatbot::Eliza.

=cut

package DJabberd::Bot::Eliza;
use strict;
use warnings;
use base 'DJabberd::Bot';
use Chatbot::Eliza;
use DJabberd::Util qw(exml);

our $logger = DJabberd::Log->get_logger();

sub initialize {
    my ($self, $opts) = @_;

    my $jid = $self->jid;

    $self->{bot} = Chatbot::Eliza->new;
    $self->{bot}->name($opts->{chatname} || $jid->node);
}

sub handle_message {
    my ($self, $stanza) = @_;

    my $body;
    foreach my $child ($stanza->children_elements) {
        if ($child->{element} eq 'body') {
            $body = $child;
            last;
        }
    }
    $logger->logdie("Can't find a body in incoming message") unless $body;
    return $self->{bot}->transform($body->first_child);
}

1;


