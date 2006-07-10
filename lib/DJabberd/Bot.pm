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
    DJabberd::Presence->set_local_presence($self->{jid}, DJabberd::Presence->available(from => $self->{jid}));
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
}

1;
