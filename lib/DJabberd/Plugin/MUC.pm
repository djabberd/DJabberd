package DJabberd::Plugin::MUC;
use strict;
use base 'DJabberd::Plugin';
use warnings;
use DBI;
use DJabberd::Plugin::MUC::Room;
our $logger = DJabberd::Log->get_logger();


sub set_config_subdomain {
    my ($self, $subdomain ) = @_;
    $self->{subdomain} = $subdomain;
}


sub register {
    my ($self, $vhost) = @_;


    if($self->{subdomain}) {
        $self->{domain} = $self->{subdomain} . "." . $vhost->server_name;
    } else {
        $self->{domain} = $vhost->server_name;
        # we need to check if a jid exist before we create things
        $self->{need_jid_check}++;
    }

    $logger->info("Starting up multiuser chat on '$self->{domain}'");

    $self->{vhost} = $vhost;


    my $cb = sub {
        my ($vh, $cb, $iq) = @_;

        warn $iq->first_child->element . "";;


        # XXX: shouldn't check for muc in x to support GC
        if(($iq->to_jid->domain           ne $self->{domain})
           || ($iq->first_child->element  ne '{http://jabber.org/protocol/muc}x')) {
            $cb->decline;
            return;
        }
        warn "got a muc presence package";

        if($iq->to_jid->resource ne '') {
            # TODO: send an error, no nickname specified error 400 jid malfomed
        }

        if($self->{need_jid_check}) {
            # should check if this jid is taken on this server
        }

        $self->join_room($iq->to_jid->node, $iq->to_jid->resource, $iq->from_jid);
    };
    $vhost->register_hook("DirectedPresence",$cb);


}

sub join_room {
    my ($self, $room_name, $nickname, $jid) = @_;
    my $room = $self->get_room($room_name);
    $room->add($nickname, $jid);
}


sub get_room {
    my ($self, $room_name) = @_;
    return $self->{rooms}->{$room_name} ||= DJabberd::Plugin::MUC::Room->new($room_name, $self->{domain}, $self->{vhost});

}

1;
