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

}
