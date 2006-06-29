package DJabberd::HookDocs;
use strict;
use vars qw(%hook);

sub allow_hook {
    my ($class, $ph) = @_;
    $hook{$ph} = {};
}

# STUBS FOR NOW

# TODO: make run_hook_chain() also validate (perhaps only in dev mode), the parameters
# are of right count and type as documented

# TODO: make run_hook_chain() also validate callback methods are documented

$hook{'filter_incoming_client'} = {};
$hook{'switch_incoming_client'} = {};
$hook{'filter_incoming_server'} = {};
$hook{'switch_incoming_server'} = {};


$hook{'GetPassword'} = {
    des => "Lookup a user's plaintext password",
    args => [ "username" => '$username', "conn" => 'Connection', ],
    callbacks => {
        set => ['password'],
    },
};

$hook{'CheckCleartext'} = {
    des => "Check a user's plaintext password",
    args => [ "username" => '$username', "conn" => 'Connection', 'password' => '$password', ],
    callbacks => {
        accept => [],
        reject => [],
    },
};

$hook{'CheckDigest'} = {
    des => "Check the non-SASL-auth digest field to see if it matches digest of password+streamid",
    args => [ "username" => '$username', "conn" => 'Connection', 'digest' => '$digest', ],
    callbacks => {
        accept => [],
        reject => [],
    },
};

$hook{'CheckJID'} = {
    des => "Check if this knows about this JID",
    args => [ "username" => '$username', "conn" => 'Connection', ],
    callbacks => {
        accept => [],
        reject => [],
    },
};


$hook{'pre_stanza_write'} = {
    des => "Called before a stanza is written to a user.  Default action if all declined is to just deliver it.",
};

$hook{'c2s-iq'} = {};
$hook{'deliver'} = {
    args => ['Stanza'],
};

$hook{'RosterGet'} = {
    args => ['JID'],
    callbacks => {
        set_roster => [ 'Roster' ],
    },
    des  => "Retrieve user JID's roster.",
};

$hook{'RosterRemoveItem'} = {
    args => ['RosterItem'],
    des  => "Remove an provided RosterItem from connection's roster.",
};

$hook{'RosterAddUpdateItem'} = {
    args => ['RosterItem'],
    callback => {
        done => [ 'RosterItem' ],
    },
    des => "Called when client adds or modifies a roster item.  This doesn't effect the subscription state of the roster item.  In fact, the provided RosterItem object will always have a subscription state of 'none'.  If the roster storage plugin doesn't yet have this item in the list, it should be added with the provided state of 'none'.  However, if this is an update you should ignore the RosterItem's subscription value (which will be none, and potentially override what was previously set by other methods).  This hook must return back to the 'done' callback the resultant RosterItem, with the actual subscription value set.",
};

$hook{'RosterLoadItem'} = {
    args => ['JID', 'JID'],
    callback => {
        error => [ 'reason' ],
        set   => [ 'RosterItem' ],  # or undef if second JID not in first JID's roster
    },
    des  => "Called to load first JID's rosteritem of second given JID.",
};

$hook{'RosterSetItem'} = {
    args => ['JID', 'RosterItem'],
    callback => {
        error => [ 'reason' ],
        done  => [],
    },
    des  => "Called to set an item in a JID's roster.",
};

$hook{'PresenceCheck'} = {
    args => ['JID', 'CODE'],
    callback => {
        decline => [],
    },
    des => "Called to request each hook chain item calls the given CODE with parameters (JID,DJabberd::Presence) for each full JID and last presence for that full JID that is based on the provided short JID (the first parameter).  Each hook chain item is just expected to call the CODE subref 0 or more times, then decline.",
};

$hook{'RegisterJID'} = {
    args => [username => '$user', password => '$pass'],
    callback => {
        saved => {},
        conflict => {},
    },
    des => "In-band registration, way for core to ask auth system to provision an account.",
};

$hook{'UnregisterJID'} = {
    args => [username => '$user'],
    callback => {
        deleted => {},
        notfound => {},
    },
    des => "In-band unregistration, way for core to ask auth system to unprovision an account.",
};

$hook{'RosterWipe'} = {
    args => ['JID'],
    callback => {
        done => {},
        error => {},
    },
    des => "Wipe a user's roster",
};

1;
