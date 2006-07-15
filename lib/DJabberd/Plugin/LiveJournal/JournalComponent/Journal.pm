
package DJabberd::Plugin::LiveJournal::JournalComponent::Journal;

use strict;
use warnings;
use base qw(DJabberd::Component::Node);
use DJabberd::Component;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub handle_message {
    my ($self, $vhost, $stanza) = @_;
    
    my $type = $stanza->attrs->{'{}type'};
    
    if ($type eq 'normal' || !defined($type)) {
        $self->handle_normal_message($vhost, $stanza);
    }
    elsif ($type eq 'chat') {
        $self->handle_chat($vhost, $stanza);
    }
}

sub handle_chat {
    my ($self, $vhost, $stanza) = @_;
    
    # Journal-posting chatbot
    
    my $response = $stanza->make_response;
    $response->set_raw("<body>I don't understand.</body>");
    $response->deliver($vhost);
}

sub handle_normal_message {
    my ($self, $vhost, $stanza) = @_;
    
    my $response = $stanza->make_response;
    $response->set_raw("<subject>Success!</body><body>Entry posted. But not really.</body>");
    $response->deliver($vhost);
   
}

1;

