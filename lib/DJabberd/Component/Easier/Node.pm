
package DJabberd::Component::Easier::Node;

use base qw(DJabberd::Agent);
use DJabberd::Util qw(exml);
use strict;
use warnings;

# ICK: This is really "new", but it's called "fetch" to avoid collision with the Plugin "new" method
sub fetch {
    my ($class, $nodename, $cmpnt) = @_;
    return bless {
        easier_node_name => $nodename,
        easier_node_component => $cmpnt,
        easier_node_iqcb => {},
    }, $class;
}

sub name {
    return $_[0]->nodename;
}

sub nodename {
    return $_[0]->{easier_node_name};
}

sub bare_jid {
    return new DJabberd::JID($_[0]->{easier_node_name}."@".$_[0]->{easier_node_component}->domain);
}

sub resource_jid {
    my ($self, $resourcename) = @_;
    return new DJabberd::JID($self->bare_jid->as_string()."/".$resourcename);
}

sub component {
    return $_[0]->{easier_node_component};
}

sub vcard {
    my ($self, $requester_jid) = @_;

    # Empty vCard by default
    return "<NICKNAME>".exml($self->name)."</NICKNAME>";
}

1;
