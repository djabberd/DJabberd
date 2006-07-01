
package DJabberd::Plugin::VCard::InMemoryOnly;
use strict;
use base 'DJabberd::Plugin::VCard';
use warnings;
use DBI;

our $logger = DJabberd::Log->get_logger();

sub load_vcard {
    my ($self, $user) = @_;
    $self->{vcards} ||= {};
    if (exists $self->{vcards}{$user}) {
        return $self->{vcards}{$user};
    } else {
        return undef;
    }
}

sub store_vcard {
    my ($self, $user, $vcard) = @_;
    $self->{vcards} ||= {};
    $self->{vcards}{$user} = $vcard->as_xml;
}

1;
