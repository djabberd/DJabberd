
# An abstract base class providing a higher-level API for
# component implementation.
# Subclasses can override different functions to override
# behavior at a variety of levels.

package DJabberd::Component::Easier;
use base qw(DJabberd::Component);
use strict;
use DJabberd::Util qw(exml);
use DJabberd::JID;


sub handle_stanza {
    my ($self, $vhost, $cb, $stanza) = @_;

    if ($stanza->to_jid->node) {
        $self->stanza_to_node($vhost, $stanza);
    }
    else {
        $self->stanza_to_service($vhost, $stanza);
    }

    # We consider all stanzas as being delivered, even though
    # the component might well have ignored them.
    $cb->delivered;
}


sub stanza_to_node {
    my ($self, $vhost, $stanza) = @_;

    return $self->iq_to_node($vhost, $stanza) if $stanza->isa('DJabberd::IQ');
    return $self->message_to_node($vhost, $stanza) if $stanza->isa('DJabberd::Message');
    return $self->presence_to_node($vhost, $stanza) if $stanza->isa('DJabberd::Presence');

}

sub stanza_to_service {
    my ($self, $vhost, $stanza) = @_;
    
    return $self->iq_to_service($vhost, $stanza) if $stanza->isa('DJabberd::IQ');
    return $self->message_to_service($vhost, $stanza) if $stanza->isa('DJabberd::Message');
    return $self->presence_to_service($vhost, $stanza) if $stanza->isa('DJabberd::Presence');
    
}

### Service Handlers

sub iq_to_service {
    my ($self, $vhost, $stanza) = @_;

    # Default implementation provides higher-level handling of some common
    # requests a component might get.
    # Many subclasses will want to override this but use SUPER to retain
    # this existing functionality, or register callbacks using register_service_iq_handler.
    
    my $sig = $stanza->signature;
    
    if ($self->{easier_cb_service_iq} && $self->{easier_cb_service_iq}{$sig}) {
        return $self->{easier_cb_service_iq}{$sig}->($vhost, $stanza);
    }
    
    return $self->iq_to_service_disco_info($vhost,$stanza) if $sig eq 'get-{http://jabber.org/protocol/disco#info}query';
    return $self->iq_to_service_disco_items($vhost,$stanza) if $sig eq 'get-{http://jabber.org/protocol/disco#items}query';

}

sub register_service_iq_handler {
    my ($self, $signature, $handler) = @_;
    
    $self->{easier_cb_service_iq} ||= {};
    $self->{easier_cb_service_iq}{$signature} = $handler;
}

sub iq_to_service_disco_info {
    my ($self, $vhost, $stanza) = @_;
    
    my $features = $self->get_service_features();
    my $identities = $self->get_service_identities();
    
    my $response = $stanza->make_response();

    my $xml = "<query>" .
              join('',map({ "<identity category='".exml($_->[0])."' type='".exml($_->[1])."' name='".exml($_->[2])."'/>" } @$identities)) .
              join('',map({ "<feature var='".exml($_)."' />" } @$features)) .
              "</query>";
    $response->set_raw($xml);
    $response->deliver($vhost);
    
}

sub iq_to_service_disco_items {
    my ($self, $vhost, $stanza) = @_;
    
    my $items = $self->get_service_children();
    
    my $response = $stanza->make_response();

    my $xml = "<query>" . join('',map({ "<item jid='".exml($_->[0])."' name='".exml($_->[1])."'/>" } @$items)) . "</query>";
    $response->set_raw($xml);
    $response->deliver($vhost);
    
}

sub get_service_name {
    my ($self) = @_;
    
    return $self->domain;
}

sub get_service_identities {
    my ($self) = @_;
    
    # Use a generic identity by default because some clients
    # get upset if a JID has no identities.
    # Subclasses really should specialize this.
    return [
        [ 'heirarchy', 'branch', $self->get_service_name ],
    ];
}

sub get_service_features {
    my ($self) = @_;
    
    # We know we support disco, at least!
    return [
        'http://jabber.org/protocol/disco#info',
        'http://jabber.org/protocol/disco#items',
    ];
}

sub get_service_children {
    my ($self) = @_;

    # No children in default implementation.
    return [];
}

sub message_to_service {
    my ($self, $vhost, $stanza) = @_;
    
    # Do nothing by default
}

sub presence_to_service {
    my ($self, $vhost, $stanza) = @_;
    
    # Do nothing by default
}

### Node Handlers

sub iq_to_node {
    my ($self, $vhost, $stanza) = @_;

    my $sig = $stanza->signature;

    if ($self->{easier_cb_node_iq} && $self->{easier_cb_node_iq}{$sig}) {
        return $self->{easier_cb_node_iq}{$sig}->($vhost, $stanza);
    }
}

sub register_node_iq_handler {
    my ($self, $signature, $handler) = @_;
    
    $self->{easier_cb_node_iq} ||= {};
    $self->{easier_cb_node_iq}{$signature} = $handler;
}

sub message_to_node {
    my ($self, $vhost, $stanza) = @_;
    
    # Do nothing by default
}

sub presence_to_node {
    my ($self, $vhost, $stanza) = @_;
    
    # Do nothing by default
}

1;
