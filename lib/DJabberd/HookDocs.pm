package DJabberd::HookDocs;
use strict;
use vars qw(%hook);

# STUBS FOR NOW
# TODO: make run_hook_chain() also validate (perhaps only in dev mode), the parameters
# are of right count and type as documented
$hook{'filter_incoming_client'} = {};
$hook{'switch_incoming_client'} = {};
$hook{'filter_incoming_server'} = {};
$hook{'switch_incoming_server'} = {};
$hook{'c2s-iq'} = {};
$hook{'deliver'} = {};
$hook{'Auth'} = {};
$hook{'RosterGet'} = {};
$hook{'RosterRemoveItem'} = {};
$hook{'RosterSetItem'} = {};

1;
