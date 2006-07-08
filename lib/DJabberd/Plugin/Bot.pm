
package DJabberd::Plugin::Bot;

use strict;
use warnings;
use base 'DJabberd::Plugin';
use DJabberd::JID;
use Carp;
use Scalar::Util;

our $logger = DJabberd::Log->get_logger();

sub set_config_nodename {
    my ($self, $nodename) = @_;
    $self->{nodename} = $nodename;
}

sub set_config_resource {
    my ($self, $resource) = @_;
    $self->{resource} = $resource;
}

sub set_config_class {
    my ($self, $class) = @_;
    $logger->logdie("Invalid classname $class") if $class =~ /[^\w:]/;
    $self->{class} = $class;
}

# Pass any unrecognised configuration parameters on to the bot itself
sub set_config__option {
    my ($self, $key, $val) = @_;
    $self->{bot_opts} ||= {};
    $self->{bot_opts}{$key} = $val;
}

sub finalize {
    my ($self) = @_;

    Carp::confess("A bot needs a nodename") unless $self->{nodename};
    $self->{resource} ||= "bot";

    my $loaded = eval "use $self->{class}; 1;";
    $logger->logdie("Unable to load component class $self->{class}: $@") unless $loaded;

}

sub register {
    my ($self, $vhost) = @_;
    
    my $jid_string = "$self->{nodename}\@" . $vhost->server_name . "/$self->{resource}";
    $logger->info("Registering bot $self->{class} as $jid_string");
    $self->{jid} = DJabberd::JID->new($jid_string);

    $self->{bot} = $self->{class}->new($self->{jid}, $self->{bot_opts});
    $logger->logdie("Failed to instantiate bot $self->{class}") unless ref $self->{bot};

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

}

sub send_stanza {
    my ($self, $stanza) = @_;

    my $body = "";
    my $reply;
    if ($stanza->isa('DJabberd::Message')) {
        my ($text, $html) = $self->{bot}->handle_message($stanza);
        if ($text) {
            $body .= "<body>". DJabberd::Util::exml($text) . "</body>";
        }
        if ($html) {
            #  <html xmlns='http://jabber.org/protocol/xhtml-im'>
            # <body xmlns='http://www.w3.org/1999/xhtml'>
            $body .= $html;
            # </body></html>
        }
        $reply = DJabberd::Message->new('jabber:client', 'message', { '{}type' => 'chat', '{}to' => $stanza->from, '{}from' => $self->{jid} }, []);
    } else {
        $logger->warn("Ignoring $stanza");
    }

    if($body && $reply) {
        $reply->set_raw($body);
        $reply->deliver($self->{vhost});
    }
}

sub write {
    # currently don't do anything here
    $logger->warn("Ignoring writes");
}

# FIXME: Should this really be get_status_type, or something?
sub is_available {
    return $_[0]->{bot}->is_available;
}

sub requested_roster { 0; } # Bots don't request rosters
