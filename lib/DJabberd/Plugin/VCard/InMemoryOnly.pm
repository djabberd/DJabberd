
package DJabberd::Plugin::VCard::InMemoryOnly;
use strict;
use base 'DJabberd::Plugin::VCard';
use warnings;
use DBI;

our $logger = DJabberd::Log->get_logger();

our %vcards;

sub load_vcard {
    my ($self, $user) = @_;
    if (exists $vcards{$user}) {
        return $vcards{$user};
    } else {
        return undef;
    }
}

sub store_vcard {
    my ($self, $user, $vcard) = @_;
    $vcards{$user} = $vcard->as_xml;
}

1;
