package DJabberd::Bot::Demo;
use strict;
use warnings;

use base qw[DJabberd::Bot];

require Carp;

### this initializes a log object
our $logger = DJabberd::Log->get_logger;

### When this plugin is called, it calls the following methods:
### sub new 
###     * inherited from DJabberd::Bot, which inherits from DJabberd::Plugin
###     * called when the <Plugin> directives in the configuration file are read
###     * returns an object of this class
###     * See DJabberd::Plugin for details
###
### sub finalize 
###     * inherited from DJabberd::Bot, which inherits from DJabberd::Plugin
###     * callback before the server starts up. allows you to finalize or throw
###       an exception
###
### sub register
###     * inherited from DJabberd::Bot, which inherits from DJabberd::Plugin
###     * must be overridden by your class if DJabberd::Bot does not implement
###       what you want
###     * does all the necessary setup steps for your bot
###     * See DJabberd::Bot and DJabberd::Plugin for details
###
### sub set_config_ARGUMENT_PROVIDED_IN_CONFIGURATION
###     * inherited from DJabberd::Bot, which inherits from DJabberd::Plugin
###     * must be implemented by your class if not implemented in DJabberd::Bot
###     * See DJabberd::Bot and DJabberd::Plugin for details

sub register {
    my $self    = shift;
    my $vhost   = shift;
    my $server  = $vhost->server;

    ### this must be called first, so all kinds of things get set up
    ### for us, including the JID
    $self->SUPER::register( $vhost );
    
    ### sample info message showing us the bot started up
    $logger->info( "Starting up Demo Bot" );
}

### sub to handle the 'name' configuration directive
sub set_config_name {
    my( $self, $name ) = @_;
    $self->{'name'} = $name;
}

### retrieve the bots name as set in the configuration,
### falling back to a default
sub name {
    my $self = shift;
    return $self->{'name'} || 'Unknown Bot';
}    

### process any incoming messages
sub process_text {
    my ($self, $text, $from, $ctx ) = @_;

    ### log the message we got
    $logger->info(  "Got '$text' from $from" );

    ### and echo it straight back to them
    $ctx->reply(    "Echo: $text" );

    return 1;
}

1;
