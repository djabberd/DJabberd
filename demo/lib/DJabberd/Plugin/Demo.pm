package DJabberd::Plugin::Demo;

use strict;
use warnings;

require DJabberd::Plugin;
use base 'DJabberd::Plugin';

### this plugin sets up a bot and subscribes any connecting user to it
### therefor, we need to include these libraries
# use Djabberd::Callback;
# use DJabberd::Bot::Demo;
# use DJabberd::Subscription;
# use DJabberd::RosterStorage;

### initialize a logger
our $logger = DJabberd::Log->get_logger();

### register our plugin. we don't need to do any actions now, but we're
### registering two hooks to be called on certain events. Hooks are implemented
### using callbacks. To see which hooks are available, read 'DJabberd::HookDocs'.
### To see how callbacks work, see 'DJabberd::Callback'.
sub register {
    my($self, $vhost) = @_;
    
    ### when the client asks for the roster, call this hook first. This allows
    ### us to manipulate the roster before the client sees it.
    $vhost->register_hook("RosterGet",              \&hook_on_roster_get);

    ### when we get any incoming messages, call this hook first. This allows us
    ### to dispatch any messages for our bot to the bot object
    $vhost->register_hook("switch_incoming_client", \&hook_switch_incoming_client);
}

### hook to call when a roster is requsted.
sub hook_on_roster_get {
    ### our arguments are:
    ### $vhost: The vhost object the client connected to. See DJabberd::VHost
    ### $cb:    The callback for this hook. See DJabberd::HookDocs
    ### $jis:   The client object that connected to us. See DJabberd::JID
    my($vhost, $cb, $jid) = @_;
    
    ### First, retrieve the roster storage object, so we can add something
    ### to the roster
    my $rs          = DJabberd::RosterStorage->singleton;

    ### next, retrieve the JID (client id) of our bot, since we want to add
    ### him to this users roster
    my $bot         = DJabberd::Bot::Demo->singleton;
    
    ### next, create a rosteritem. This states how the bot is to be linked
    ### to our user. The JID is the internal ID, name is the pretty printed
    ### name that the user will see in his buddy list. Subscription is a
    ### DJabberd::Subscription object showing how the users are linked.
    ### See DJabberd::Subscription for all possibilities, but basically '3'
    ### means they are mutual friends.
    my $ritem       = DJabberd::RosterItem->new( 
                        jid             => $bot->jid->as_bare_string, 
                        name            => $bot->name,
                                        ### the bitmask '3' signifies mutual
                                        ### subscription
                        subscription    => DJabberd::Subscription->from_bitmask( 3 ),
                      );

    ### Now we create a callback for 'addupdate_roster_item' to call when
    ### it processes the roster item. This is a callback that confroms 
    ### exactly to what DJabberd::HookDocs tells us about the hook
    ### 'RosterAddUpdateItem'.
    my $rs_cb = DJabberd::Callback->new({
        done => sub {
            my $ri = shift;

            ### pretty print message showing us that the linking worked
            $logger->debug( "Automatically linked ". $ritem->jid .' to '. 
                            $jid->as_bare_string );
        },
    });

    ### Update the roster to add the bot (as described in $ritem) to the
    ### client (as described in $jid). Will call callback $rs_cb when done.
    $rs->addupdate_roster_item( $rs_cb, $jid, $ritem );
    
    ### callbacks have the possiblity to stop the callback chain from 
    ### continuing, by either throwing an error or telling the callback
    ### mechanism it is done. In our case, we want the chain to continue.
    ### See DJabberd::HookDocs for details on this.
    $cb->decline;
}

### hook to call when an event comes in
sub hook_switch_incoming_client {
    ### our arguments are:
    ### $vhost: The vhost object the client connected to. See DJabberd::VHost
    ### $cb:    The callback for this hook. See DJabberd::HookDocs
    ### $obj:   An object representing the event that occurred. Can be various
    ###         classes, but all inherit from DJabberd::XMLElement
    my ($vhost, $cb, $obj) = @_;

    ### retrieve the bot object
    my $bot  = DJabberd::Bot::Demo->singleton;

    ### We only care about messages that are addressed to our bot. So compare
    ### the JID of the recipient to the JID of our bot. If they match, it was
    ### addressed to the bot.
    ### Also, the only events we are interested in are messages. So if this
    ### is not a message, we just move on.
    if( ( lc $obj->to_jid eq lc $bot->jid->as_bare_string ) and
        UNIVERSAL::isa( $obj, "DJabberd::Message" ) 
    ) {
        ### inspect all the nested messages. There's different types of
        ### messages that the client can send, including 'composing' and
        ### 'paused' (which can be used to show the user is typing).
        ### We only care about a body being sent to us, so skip all others.
        for my $child ( $obj->children ) {
            ### don't care about composing/paused/etc
            next unless '{jabber:client}body' eq $child->element;

            ### this is the raw message;
            my $text = $child->first_child;
            
            ### get a context, so the bot can use it to write it's message
            ### back
            my $ctx  = $bot->get_context("stanza", $obj->from_jid);

            ### Process the text we received
            $bot->process_text( $text, $obj->from_jid, $ctx ); 

            ### there's nothing else to be done in this chain now, as the
            ### bot has handled the reply. So stop the chain and return.
            $cb->stop_chain;
            return;
        }
    }

    ### we didn't handle this event, so the callback chain should continue
    $cb->decline;
}

1;

