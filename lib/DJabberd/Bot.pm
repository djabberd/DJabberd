package DJabberd::Bot;
use strict;
use warnings;
use base 'DJabberd::Plugin';
use DJabberd::JID;
use Carp;
use Scalar::Util;
use List::Util qw(first);
use DJabberd::BotContext;

our $logger = DJabberd::Log->get_logger();

### store the object in a closure, so we can retrieve it later
{   my $singleton;
    sub singleton { $singleton };
    
    sub new {
        my $self = shift;
        $singleton = $self->SUPER::new( @_ );
    }
}

sub set_config_nodename {
    my ($self, $nodename) = @_;
    $self->{nodename} = $nodename;
}

sub set_config_resource {
    my ($self, $resource) = @_;
    $self->{resource} = $resource;
}

sub finalize {
    my ($self) = @_;

    Carp::confess("Bot needs a nodename") unless $self->{nodename};
    $self->{resource} ||= "bot";
}

sub jid {
    return $_[0]->{jid};
}

sub bound_jid {
    return $_[0]->jid;
}

sub vhost {
    return $_[0]->{vhost};
}

sub register {
    my ($self, $vhost) = @_;
    $self->{jid} = DJabberd::JID->new("$self->{nodename}\@" . $vhost->server_name . "/$self->{resource}");

    $self->{vhost} = $vhost;
    Scalar::Util::weaken($self->{vhost});

    my $regcb = DJabberd::Callback->new({
        registered => sub {
            $logger->debug("Bot $self->{jid} is now registered");
        },
        error => sub {
            $logger->error("Bot $self->{jid} failed to register");
            },
    });

    $vhost->register_jid($self->{jid}, $self , $regcb);
    DJabberd::Presence->set_local_presence(
        $self->{jid}, 
        DJabberd::Presence->available( from => $self->{jid} )
    );
}

# no-op bot logic:
sub process_text {
    my ($self, $text, $from, $cb) = @_;
    $cb->done;
}

# TODO: not yet used.
sub context_timeout { 300 }

sub get_context {
    my ($self, $method, $fromjid) = @_;
    # TODO: cache these, and time them out according to $self->context_timeout
    if ($method eq "stanza") {
        return DJabberd::BotContext->new($self->{vhost}, $method, $fromjid, $self->jid);
    }
}


############################################################################
# Connection-like methods, for when we're pretending to be a roster item, and registered
# ourselves with jidmap.  (as opposed to being a component)
############################################################################

sub write {
    # currently don't do anything here
    $logger->warn("Ignoring writes");
}

sub is_available { 1 }

sub requested_roster { 0 }

sub send_stanza {
    my ($self, $stanza) = @_;

    if ($stanza->isa('DJabberd::Message')) {
        my ($text, $html);
        # find the plaintext
        {
            my $body = first { $_->element_name eq "body" } $stanza->children_elements
                or return;
            $text = $body->first_child
                or return;
        }
        # find the HTML text
        if (my $htmlnode = first { $_->element eq "{http://jabber.org/protocol/xhtml-im}html" }
            $stanza->children_elements)
        {
            my $bodynode = $htmlnode->first_element;
            if ($bodynode->element eq "{http://www.w3.org/1999/xhtml}body") {
                $html = $bodynode->innards_as_xml;
            }
        }

        my $ctx = $self->get_context("stanza", $stanza->from_jid);
        $ctx->add_text($text, $html);
        $self->process_text($text, $stanza->from_jid, $ctx);
        return;
    }
    elsif ($stanza->isa('DJabberd::Presence')) {
        # Most presence-related stuff is handled by the server itself, However, we still
        # need to handle presence subscription requests.
        my $type = $stanza->attr('{}type');
        
        if ($type eq 'subscribe') {
            $logger->debug("Accepting presence subscripton request from ", $stanza->from_jid->as_string);
            my $response = DJabberd::Presence->new('jabber:client', 'presence', {
                '{}type' => 'chat',
                '{}to' => $stanza->from_jid->as_string,
                '{}type' => 'subscribed',
            }, []);
            $self->send_stanza_as_client($response);
        }

    }

}

# Since DJabberd::Bot is acting like a client, it must deliver messages using
# this method which does the same thing as a DJabberd::Connection::ClientIn would
# do if a stanza was recieved from a real client.
sub send_stanza_as_client {
    my ($self, $stanza) = @_;
    $self->vhost->hook_chain_fast(
        "filter_incoming_client",
        [ $stanza, $self ],
        {
            reject => sub { },  # just stops the chain
        },
        \&filter_incoming_client_builtin,
    );
}
sub filter_incoming_client_builtin {
    my ($vhost, $cb, $stanza, $self) = @_;

    # if no from, we set our own
    if (! $stanza->from_jid) {
        my $bj = $self->jid;
        $stanza->set_from($bj->as_string) if $bj;
    }

    $vhost->hook_chain_fast(
        "switch_incoming_client",
        [ $stanza ],
        {
            process => sub { }, # Do nothing, because we don't actually have a $conn object to pass into $stanza->process
            deliver => sub { $stanza->deliver($vhost) },
        },
        sub {
            $stanza->on_recv_from_client($self);
        },
    );
}

1;
