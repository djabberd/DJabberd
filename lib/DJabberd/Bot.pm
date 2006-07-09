

=head1 NAME

DJabberd::Bot - Abstract class representing a bot in DJabberd

=head1 SYNOPSIS

    package MyPackage::DJabberd::MyBot;
    use base DJabberd::Bot;
    
    sub initialize {
        my ($self, $opts) = @_;
        
        # ... perform initialization
    }
    
    sub handle_message {
        my ($self, $stanza) = @_;
        
        # ... handle the given stanza
        
        return ("Plain text response", "<p>HTML response</p>");
    }
    
This class provides a parent class for all DJabberd bots. A bot
is a class that recieves messages sent to a particular JID and responds
to them.

DJabberd does not use bots directly. The DJabberd::Plugin::Bot plugin
can be used to expose a bot at a given JID within a VHost, or components
can instantiate bots directly to expose them as nodes in their domain.

See DJabberd::Bot::Eliza for an example bot implementation.

TODO: Write more docs

=cut


package DJabberd::Bot;

use strict;
use warnings;
use DJabberd::JID;
use Carp;
use Scalar::Util;

our $logger = DJabberd::Log->get_logger();

# Don't override this. Implement initialize($opts) instead.
sub new {
    my ($class, $opts) = @_;

    my $self = bless {}, $class;
    
    $self->initialize($opts);
    
    return $self;
}

sub initialize {}

sub handle_message {
    $logger->warn("$_[0] does not implement handle_message");
}

sub is_available { 1 }

sub requested_roster { 0 }

1;
