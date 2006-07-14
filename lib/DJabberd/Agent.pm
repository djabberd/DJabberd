
# An abstract base class providing a higher-level API for
# component/service implementation.
# Subclasses can override different functions to override
# behavior at a variety of levels.

package DJabberd::Agent;
use base qw(DJabberd::Delivery);
use strict;
use warnings;
use DJabberd::Util qw(exml);
use DJabberd::JID;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

sub handle_stanza {
    my ($self, $vhost, $stanza) = @_;

    return $self->handle_iq($vhost, $stanza) if $stanza->isa('DJabberd::IQ');
    return $self->handle_message($vhost, $stanza) if $stanza->isa('DJabberd::Message');
    return $self->handle_presence($vhost, $stanza) if $stanza->isa('DJabberd::Presence');    

}

sub deliver {

    my ($self, $vhost, $cb, $stanza) = @_;

    $logger->debug("Got a nice stanza: ".$stanza->as_summary);

    # FIXME: Maybe this should require an exact match on the vhost domain, rather than handles_domain?
    if ($self->handles_destination($stanza->to_jid, $vhost)) {
        $logger->debug("Delivering ".$stanza->element_name." stanza via agent ".$self);
        $self->handle_stanza($vhost, $stanza);
        $cb->delivered;
    }
    else {
        $logger->debug("This stanza is not for ".$vhost->server_name);
        $cb->decline;
    }

}

sub handles_destination {
    my ($self, $to_jid, $vhost) = @_;
    
    return 0;
}

sub name {
    my ($self) = @_;
    
    return "";
}

sub handle_message {
    my ($self, $vhost, $stanza) = @_;
    
    # By default, ignore the message altogether
}

sub handle_presence {
    my ($self, $vhost, $stanza) = @_;
    
    # By default, ignore the presence altogether
}

sub handle_iq {
    my ($self, $vhost, $stanza) = @_;
    
    my $sig = $stanza->signature;
    
    if ($self->{djabberd_agent_iqcb} && $self->{djabberd_agent_iqcb}{$sig}) {
        return $self->{djabberd_agent_iqcb}{$sig}->($vhost, $stanza);
    }

    return $self->handle_iq_vcard($vhost,$stanza) if $sig eq 'get-{vcard-temp}vCard';
    return $self->handle_iq_disco_info($vhost,$stanza) if $sig eq 'get-{http://jabber.org/protocol/disco#info}query';
    return $self->handle_iq_disco_items($vhost,$stanza) if $sig eq 'get-{http://jabber.org/protocol/disco#items}query';
    
    # If we've got this far, then we don't support this IQ type
    $stanza->make_error_response('501', 'cancel', 'feature-not-implemented')->deliver($vhost);
}

sub register_iq_handler {
    my ($self, $signature, $handler) = @_;
    
    $self->{easier_node_iqcb} ||= {};
    $self->{easier_node_iqcb}{$signature} = $handler;
}

sub handle_iq_vcard {
    my ($self, $vhost, $stanza) = @_;
    
    my $vcard = $self->vcard($stanza->to_jid);

    my $response = $stanza->make_response();
    $response->set_raw("<vCard xmlns='vcard-temp'>".$vcard."</vCard>");
    $response->deliver($vhost);    
}

sub handle_iq_disco_info {
    my ($self, $vhost, $stanza) = @_;

    my $features = $self->features($stanza->from_jid);
    my $identities = $self->identities($stanza->from_jid);
    
    my $response = $stanza->make_response();

    my $xml = "<query xmlns='http://jabber.org/protocol/disco#info'>" .
              join('',map({ "<identity category='".exml($_->[0])."' type='".exml($_->[1])."' name='".exml($_->[2])."'/>" } @$identities)) .
              join('',map({ "<feature var='".exml($_)."' />" } @$features)) .
              "</query>";
    $response->set_raw($xml);
    $response->deliver($vhost);
}

sub handle_iq_disco_items {
    my ($self, $vhost, $stanza) = @_;

    my $items = $self->child_services($stanza->from_jid);
    
    my $response = $stanza->make_response();

    my $xml = "<query xmlns='http://jabber.org/protocol/disco#items'>" .
              join('',map({ "<item jid='".exml($_->[0])."' name='".exml($_->[1])."'/>" } @$items)) .
              "</query>";
    $response->set_raw($xml);
    $response->deliver($vhost);
}

sub vcard {
    my ($self, $requester_jid) = @_;

    # Empty vCard by default
    return "";
}

sub features {
    my ($self, $requester_jid) = @_;
    
    # We support disco and vCards by default
    return [
        'vcard-temp',
        'http://jabber.org/protocol/disco#info',
        'http://jabber.org/protocol/disco#items',
    ];
}

sub identities {
    my ($self, $requester_jid) = @_;
    
    # No identities by default
    return [];
}

sub child_services {
    my ($self, $requester_jid) = @_;

    # None by default
    return [];
}

1;
