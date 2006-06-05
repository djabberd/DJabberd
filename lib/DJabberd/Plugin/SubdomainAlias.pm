package DJabberd::Plugin::SubdomainAlias;
use strict;
use base 'DJabberd::Plugin';
use warnings;
use DBI;

our $logger = DJabberd::Log->get_logger();


# this module just lets you add a subdomain that behaves like the main domain

sub set_config_subdomain {
    my ($self, $subdomain ) = @_;
    $self->{subdomain} = $subdomain;
}




sub register {
    my ($self, $vhost) = @_;
    $vhost->register_subdomain($self->{subdomain}, __PACKAGE__);
    my $domain = $self->{subdomain} . "." . $vhost->server_name;
    my $transform = sub {
        my ($vh, $cb, $iq) = @_;

        if ( !$iq->to_jid
             || $iq->isa("DJabberd::Stanza::DialbackResult")
             || $iq->to_jid->domain ne $domain ) {
            $cb->decline;
            return;
        }
        # FIXME: We should really create a new jid and setting it instead of messing around with the old one
        my $jid = $iq->to_jid;
        $jid->[DJabberd::JID::DOMAIN()] = $vhost->server_name;
        $cb->decline;
    };
    $vhost->register_hook("switch_incoming_client",$transform);
    $vhost->register_hook("switch_incoming_server",$transform);
}
