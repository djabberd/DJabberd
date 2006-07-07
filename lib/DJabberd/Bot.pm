
package DJabberd::Bot;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::Plugin';
use DJabberd::JID;
use Carp;
use Scalar::Util;
# don't override, or at least call SUPER to this if you do.

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

    my $handler = DJabberd::Bot::Handler->new();
    $handler->{bot} = $self;

    $vhost->register_jid($self->{jid}, $handler , $regcb);

}

package DJabberd::Bot::Handler;

sub new {
    my $class = shift;
    my $self = bless {} , $class;
    $self->{id} = "Internal Bot";
    return $self;
}

sub write {
    # currently don't do anything here
    $logger->warn("Ignoring writes");
}

sub send_stanza {
    my ($self, $stanza) = @_;


    if($stanza->isa('DJabberd::Message')) {
        $self->{bot}->handle_message($stanza);
    } else {
        $logger->warn("Ignoring $_[0]");
    }
}

sub is_available { 1 }

sub requested_roster { 0 }



1;
