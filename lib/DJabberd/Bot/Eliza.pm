
package DJabberd::Bot::Eliza;
use strict;
use warnings;
use base 'DJabberd::Bot';
use Chatbot::Eliza;
use DJabberd::Util qw(exml);

our $logger = DJabberd::Log->get_logger();

sub finalize {
    my ($self) = @_;
    $self->{nodename} ||= "eliza";
    $self->{bot} = Chatbot::Eliza->new;
    $self->{bot}->name($self->{nodename});
    $self->SUPER::finalize();
}

sub handle_message {
    my ($self, $stanza) = @_;


    my $body;
    foreach my $child ($stanza->children_elements) {
        if($child->{element} eq 'body') {
            $body = $child;
            last;
        }
    }
    $logger->logdie("Can't find a body in incoming message") unless $body;
    my $text = $body->first_child;
    my $txt_reply = $self->{bot}->transform($text);


    my $reply = DJabberd::Message->new('jabber:client', 'message', { '{}type' => 'chat', '{}to' => $stanza->from, '{}from' => $self->{jid} }, []);


    $reply->set_raw('<body>' . exml($txt_reply) . '</body>');
    $reply->deliver($self->{vhost});;
}

1;


