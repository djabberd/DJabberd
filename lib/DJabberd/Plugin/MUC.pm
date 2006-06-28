package DJabberd::Plugin::MUC;
use strict;
use base 'DJabberd::Plugin';
use warnings;
use DBI;
use Carp;
use DJabberd::Plugin::MUC::Room;
our $logger = DJabberd::Log->get_logger();


sub set_config_subdomain {
    my ($self, $subdomain ) = @_;
    $self->{subdomain} = $subdomain;
}

sub set_config_room {
    my ($self, $conf) = @_;
    #$self->{subdomain} = $subdomain;

    my ($name, $class, $args) = split(/\s+/, $conf, 3);

    croak "Invalid room name" if $name =~ /\W/;

    $self->{conf_rooms} ||= [];
    push @{$self->{conf_rooms}}, [ split(/\s+/, $conf, 3) ];
}

sub register {
    my ($self, $vhost) = @_;


    if ($self->{subdomain}) {
        $self->{domain} = $self->{subdomain} . "." . $vhost->server_name;
        $vhost->register_subdomain($self->{subdomain}, __PACKAGE__);
    } else {
        $self->{domain} = $vhost->server_name;
        # we need to check if a jid exist before we create things
        $self->{need_jid_check}++;
    }

    $logger->info("Starting up multiuser chat on '$self->{domain}'");

    if ($self->{conf_rooms}) {
        foreach my $roominfo (@{$self->{conf_rooms}}) {
            my ($name, $class, $args) = @$roominfo;

            $logger->debug("Registering room $name\@$self->{domain} implemented by $class");

            my $loaded = eval "use $class; 1;";
            croak "Failed to load room class $class: $@" if $@;
            $self->{rooms}->{$name} = $class->new_from_config($name, $self->{domain}, $self->{vhost}, $args);
        }

        $self->{conf_rooms} = undef; # Don't need this anymore
    }

    $self->{vhost} = $vhost;
    Scalar::Util::weaken($self->{vhost});

    my $deliver = sub {
        my ($vhost, $cb, $stanza) = @_;


        if ($stanza->isa("DJabberd::Presence")
            && $stanza->is_directed
            && $stanza->to_jid->domain eq $self->{domain}) {

            if ($stanza->to_jid->resource ne '') {
                # TODO: send an error, no nickname specified error 400 jid malfomed
            }

            if ($self->{need_jid_check}) {
                # should check if this jid is taken on this server
            }

            if ($stanza->is_unavailable) {
                $self->leave_room($stanza->to_jid->node, $stanza->to_jid->resource, $stanza->from_jid);
            } else {
                $self->join_room($stanza->to_jid->node, $stanza->to_jid->resource, $stanza->from_jid);
            }
            $cb->delivered;
            return;
        }


        if ($stanza->element_name ne 'message'
            || $stanza->to_jid->domain ne $self->{domain}) {
            return $cb->decline;
        }
        my $node = $stanza->to_jid->node;
        my $room = $self->{rooms}->{$node} || die "No room name $node";

        $room->send_message($stanza);
        $cb->delivered;

    };

    $vhost->register_hook('deliver',$deliver);


}

sub join_room {
    my ($self, $room_name, $nickname, $jid) = @_;
    my $room = $self->get_room($room_name);
    $room->add($nickname, $jid);
}

sub leave_room {
    my ($self, $room_name, $nickname, $jid) = @_;
    my $room = $self->get_room($room_name);
    $room->remove($nickname, $jid);
}


sub get_room {
    my ($self, $room_name) = @_;
    return $self->{rooms}->{$room_name} ||= DJabberd::Plugin::MUC::Room->new($room_name, $self->{domain}, $self->{vhost});

}

1;
