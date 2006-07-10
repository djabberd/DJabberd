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

sub process_text {
    my ($self, $text, $from, $cb) = @_;
    $cb->reply($self->{bot}->transform($text));
}

1;


