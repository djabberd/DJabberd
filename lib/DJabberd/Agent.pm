
=head1 NAME

DJabberd::Agent - Abstract base class representing a software agent that talks XMPP

=head1 SYNOPSIS

New agents are created by making a sub-class of this class. C<set_config_...> methods can
be provided to add configuration options, which will then be supported both on this class's
constructor and in a configuration file when adding your agent to a VHost as a delivery plugin.

    package MyAgent;
    
    use base qw(DJabberd::Agent);
    
    sub handles_destination {
        my ($self, $to_jid, $vhost) = @_;
        
        return ($to_jid->domain eq 'example.com' && $to_jid->node eq 'blah') ? 1 : 0;
    }
    
    sub handle_message {
        my ($self, $vhost, $stanza) = @_;
        my $response = $stanza->make_response();
        my $message = $self->{message} || "Hello, world!";
        $response->set_raw("<body>".DJabberd::Util::exml($message)."</body>");
        $response->deliver($vhost);
    }
    
    sub set_config_message {
        my ($self, $message) = @_;
        $self->{message} = $message;
    }

The following example shows how you might load the above agent class as a plugin:

    <Plugin MyAgent>
        Message Kumquats are groovy!
    </Plugin>

It is also possible to use an instance directly as an object, to delegate stanza handling
from another delivery plugin:

    my $agent = MyAgent->new(
        message => "Kumquats are groovy!",
    );
    $agent->handle_stanza($vhost, $stanza);

In this case, the caller will need to handle the delivery hook callbacks itself
in an appropriate manner, but it can be assumed that a call to C<handle_stanza>
will always "deliver" the stanza in some sense.

=head1 DESCRIPTION

This module is the basis for several other higher-level DJabberd classes which provide
an API for creating software agents that communicate over XMPP. This includes components
which serve an entire domain (see L<DJabberd::Component>) and bot-like nodes which
respond only to a specific node name in a domain (see L<DJabberd::Agent::Node>).

It is unlikely that other classes will inherit from this class directly. Most users
should inherit from one of the higher-level subclasses depending on what sort of
agent they wish to create. This class provides the basic machinery for handling
stanzas which all agents can use.

=head1 API

The API of this class is normally used by overriding certain methods in a subclass.
In many cases it is useful for these overriding methods to call into the base class
versions to get certain useful default functionality.

The C<handles_destination> method is the most important methods for inheritors to
override, since incoming stanzas will only be delivered to your class if this
method returns true the given destination JID.

It is assumed that if a true value is returned from this method you will handle the
incoming stanza in one way or another; this implies that in most cases you should
reply with some sort of error message if the stanza is unnacceptable in some way.

The more specialized abstract subclasses of this class will generally implement
C<handles_destination> in a way that is appropriate for their role, so users
of these subclasses will not need to override this method.

=cut

package DJabberd::Agent;
use base qw(DJabberd::Delivery);
use strict;
use warnings;
use DJabberd::Util qw(exml);
use DJabberd::JID;
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();

=head2 handle_stanza($self, $vhost, $stanza)

This method is the "entry point" of this class, and is called when a stanza is received
which this agent expressed a desire to handle. The default implementation dispatches
to one of the higher-level C<handle_...> methods depending on the type of stanza that
has been recieved. At present, only IQ, Message and Presence stanzas are supported.

Inheritors can override this method to do low-level stanza processing, but unless
the version from this class is invoked the higher-level processing methods will
cease to operate.

Callers that are using an agent instance as an object directly rather than having
it attached to a VHost as a plugin will generally call this method directly to
delegate stanza processing. In this case, it is the caller's responsibility to ensure
that the stanza is suitable for this agent; for example, the caller could make a call
to C<handles_destination> to determine if the stanza's destination JID is suitable.

=cut
sub handle_stanza {
    my ($self, $vhost, $stanza) = @_;

    return $self->handle_iq($vhost, $stanza) if $stanza->isa('DJabberd::IQ');
    return $self->handle_message($vhost, $stanza) if $stanza->isa('DJabberd::Message');
    return $self->handle_presence($vhost, $stanza) if $stanza->isa('DJabberd::Presence');

}

# Internal function allowing agents to be used directly as delivery plugins
sub deliver {

    my ($self, $vhost, $cb, $stanza) = @_;

    if ($self->handles_destination($stanza->to_jid, $vhost)) {
        $self->handle_stanza($vhost, $stanza);
        $cb->delivered;
    }
    else {
        $cb->decline;
    }

}

=head2 handles_destination($self, $to_jid, $vhost)

When an incoming stanza is potentially to be delivered to your instance, this method
will be called to find out if your agent is responsible for the destination JID.

This method is primarily used in the case where the agent is added directly to a VHost as a plugin.
If a true value is returned, the server will assume that your agent will handle the
stanza and will call C<handle_stanza>. If a false value is returned, the server will
continue to look for another appropriate delivery plugin to accept the stanza.

=cut
sub handles_destination {
    my ($self, $to_jid, $vhost) = @_;
    
    return 0;
}

# This method is no longer used
sub name {
    my ($self) = @_;
    
    return "";
}

=head2 handle_message($self, $vhost, $stanza)

When the default implementation of C<handle_stanza> is used, this method will be
called to handle incoming "message" stanzas. The C<$stanza> object passed in
will be an instance of L<DJabberd::Message|DJabberd::Message>.

The default implementation of this method does nothing.

=cut
sub handle_message {
    my ($self, $vhost, $stanza) = @_;
    
    # By default, ignore the message altogether
}

=head2 handle_presence($self, $vhost, $stanza)

When the default implementation of C<handle_stanza> is used, this method will be
called to handle incoming "presence" stanzas. The C<$stanza> object passed in
will be an instance of L<DJabberd::Presence|DJabberd::Presence>.

The default implementation of this method does nothing.

=cut
sub handle_presence {
    my ($self, $vhost, $stanza) = @_;
    
    # By default, ignore the presence altogether
}

=head2 handle_iq($self, $vhost, $stanza)

When the default implementation of C<handle_stanza> is used, this method will be
called to handle incoming "iq" stanzas. The C<$stanza> object passed in
will be an instance of L<DJabberd::IQ|DJabberd::IQ>.

The default implementation of this method provides built-in support for basic
service discovery and vcard queries, and also causes any registered IQ handlers
to be called when appropriate.

In most cases, it's better not to override this method completely but instead
to register an IQ handler for the particular IQ signature you are interested in
using C<register_iq_handler>.

=cut
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

=head2 $self->register_iq_handler($signature, $handler)

This method, unlike most methods of this class, is not intended to be overridden by subclasses.
Instead, subclasses should call this method to register a handler for a particular type of IQ
stanza. The default implementation of C<handle_iq> will then call the registered handlers
when an appropriate stanza is received.

C<$signature> is a string containing the IQ signature using DJabberd's standard IQ signature
format. This consists of the IQ type (C<get>, C<set>, etc) followed by a dash, then the
IQ element namespace in braces followed by the element name. For example, the signature for
a vCard get request is C<"{vcard-temp}vCard">.

C<$handler> is expected to be a CODE reference which accepts as arguments C<($vhost, $stanza>)>,
where C<$stanza> will be an instance of L<DJabberd::IQ|DJabberd::IQ>.

If a handler is supplied for a signature for which this class has built-in support, the supplied
handler will replace the built-in handler.

=cut
sub register_iq_handler {
    my ($self, $signature, $handler) = @_;
    
    $self->{djabberd_agent_iqcb} ||= {};
    $self->{djabberd_agent_iqcb}{$signature} = $handler;
}

# Internal method for handling vcard requests
sub handle_iq_vcard {
    my ($self, $vhost, $stanza) = @_;
    
    my $vcard = $self->vcard($stanza->to_jid);

    my $response = $stanza->make_response();
    $response->set_raw("<vCard xmlns='vcard-temp'>".$vcard."</vCard>");
    $response->deliver($vhost);
}

# Internal method for handling service discovery "info" requests
sub handle_iq_disco_info {
    my ($self, $vhost, $stanza) = @_;
    
    my $query = $stanza->first_element();
    my $disco_node = $query && $query->attr('{}node');

    my $features = $self->features($stanza->from_jid, $disco_node);
    my $identities = $self->identities($stanza->from_jid, $disco_node);
    
    my $response = $stanza->make_response();

    my $xml = "<query xmlns='http://jabber.org/protocol/disco#info'"
              . ($disco_node? " node='".exml($disco_node)."'" : '');
    if (@$features || @$identities) {
      $xml .= '>'
              . join('',map({ "<identity category='".exml($_->[0])."' type='".exml($_->[1])."' name='".exml($_->[2])."'/>" } @$identities))
              . join('',map({ "<feature var='".exml($_)."' />" } @$features))
              . "</query>";
     }
     else {
       $xml .= ' />';
     }
    
    $response->set_raw($xml);
    $response->deliver($vhost);
}

# Internal method for handling service discovery "items" requests
sub handle_iq_disco_items {
    my ($self, $vhost, $stanza) = @_;

    my $query = $stanza->first_element();
    my $disco_node = $query && $query->attr('{}node');

    my $items = $self->child_services($stanza->from_jid, $disco_node);
    
    my $response = $stanza->make_response();

    my $xml = "<query xmlns='http://jabber.org/protocol/disco#items'"
              . ($disco_node? " node='".exml($disco_node)."'" : '');
    
    if (@$items) {
      $xml .= '>'
              . join('',map({ "<item jid='".exml($_->[0])."' name='".exml($_->[1])."'/>" } @$items))
              . "</query>";
    }
    else {
      $xml .= ' />';
    }
      
    $response->set_raw($xml);
    $response->deliver($vhost);
}

=head2 vcard($self, $requester_jid)

Called by this class's built-in vCard implementation to get the contents of the vCard of
this agent. Subclasses should override this and return a string containing the XML
representing the body of the vcard to be returned, without the C<vCard> container element.

The default implementation simply returns an empty vCard. This is preferable to not returning
a response at all, because some clients do sub-optimal things which a vCard requests fails.

=cut
sub vcard {
    my ($self, $requester_jid) = @_;

    # Empty vCard by default
    return "";
}

=head2 features($self, $requester_jid)

Called by this class's built-in Service Discovery implementation to get a list of
"features" supported by this agent. Subclasses should override this and return an
ARRAY ref containing a list of strings containing feature URIs.

The default implementation returns the correct feature URIs to indicate support
for vCards and Service Discovery. It is suggested that overriding methods initially
call into the parent class to obtain the default list and then append their own
features to the list as appropriate.

=cut
sub features {
    my ($self, $requester_jid) = @_;
    
    # We support disco and vCards by default
    return [
        'vcard-temp',
        'http://jabber.org/protocol/disco#info',
        'http://jabber.org/protocol/disco#items',
    ];
}

=head2 identities($self, $requester_jid)

Called by this class's built-in Service Discovery implementation to get a list of
"identities" exposed by this agent. Subclasses should override this and return an
ARRAY ref containing a list of ARRAY refs of the form C<[$category,$type,$name]>,
where these values correspond to the attributes of the same name in the Service
Discovery specification (XEP-0030).

For example, it may be appropriate for an agent providing a multi-user conference
room to return the identity C<["conference","text","General Discussion"]>.

The default implementation currently returns an empty list. It is suggested that
overriding methods initially call into the parent class to obtain the default
list and then append their own features to the list as appropriate. Although
the list returned by this class is currently empty, the higher-level abstract
subclasses may add their own identities to this list.

=cut
sub identities {
    my ($self, $requester_jid) = @_;
    
    # No identities by default
    return [];
}

=head2 child_services($self, $requester_jid)

Called by this class's built-in Service Discovery implementation to get a list of
child services referenced by this agent. Subclasses should override this and return an
ARRAY ref containing a list of ARRAY refs of the form C<[$jid,$name]>,
where these values correspond to the attributes of the same name in the Service
Discovery specification (XEP-0030).

The default implementation currently returns an empty list. It is suggested that
overriding methods initially call into the parent class to obtain the default
list and then append their own features to the list as appropriate. Although
the list returned by this class is currently empty, the higher-level abstract
subclasses may add their own child services to this list.

=cut
sub child_services {
    my ($self, $requester_jid) = @_;

    # None by default
    return [];
}

=head1 SEE ALSO

See also L<DJabberd::Component>, L<DJabberd::Agent::Node>.

=head1 COPYRIGHT

Copyright 2007-2008 Martin Atkins

This module is part of the DJabberd distribution and is covered by the distribution's
overall licence.

=cut

1;
