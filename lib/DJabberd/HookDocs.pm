package DJabberd::HookDocs;
use strict;
use vars qw(%hook);

# STUBS FOR NOW

# TODO: make run_hook_chain() also validate (perhaps only in dev mode), the parameters
# are of right count and type as documented

# TODO: make run_hook_chain() also validate callback methods are documented

$hook{'filter_incoming_client'} = {};
$hook{'switch_incoming_client'} = {};
$hook{'filter_incoming_server'} = {};
$hook{'switch_incoming_server'} = {};
$hook{'c2s-iq'} = {};
$hook{'deliver'} = {};
$hook{'Auth'} = {};

$hook{'RosterGet'} = {
    args => [],
    callbacks => {

    },
    des  => "Retrieve a user's roster.",
};

$hook{'RosterRemoveItem'} = {
    args => ['RosterItem'],
    des  => "Remove an provided RosterItem from connection's roster.",
};

$hook{'RosterAddUpdateItem'} = {
    args => ['RosterItem'],
    des => "Called when client adds or modifies a roster item.  This doesn't effect the subscription state of the roster item.  In fact, the provided RosterItem object will always have a subscription state of 'none'.  If the roster storage plugin doesn't yet have this item in the list, it should be added with the provided state of 'none'.  However, if this is an update you should ignore the RosterItem's subscription value (which will be none, and potentially override what was previously set by other methods).",
};

$hook{'RosterSubscribe'} = {
    args => ['JID'],
    des  => "Called when a connection wants to subscribe to another JID's presence.  Hook is responsible for updating the roster with the new subscription pending substate.",
};

1;
