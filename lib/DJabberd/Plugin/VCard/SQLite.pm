
package DJabberd::Plugin::VCard::SQLite;
use strict;
use base 'DJabberd::Plugin::VCard';
use warnings;
use DBI;

our $logger = DJabberd::Log->get_logger();

sub set_config_storage {
    my ($self, $dbfile) = @_;
    $self->{dbfile} = $dbfile;
}


sub finalize {
    my $self = shift;

    $logger->error_die("No 'Database' configured'") unless $self->{dbfile};

    my $dbh = DBI->connect_cached("dbi:SQLite:dbname=$self->{dbfile}","","", { RaiseError => 1, PrintError => 0, AutoCommit => 1 });
    $self->{dbh} = $dbh;
    $self->check_install_schema;
    $logger->info("Loaded SQLite VCArd using file '$self->{dbfile}'");

    $self->SUPER::finalize;
}


sub load_vcard {
    my ($self, $user) = @_;

    my $vcard = $self->{dbh}->selectrow_hashref("SELECT * FROM vcard WHERE jid=?",
                                         undef, $user);


    return unless $vcard;
    return $vcard->{vcard};
}

sub store_vcard {
    my ($self, $user, $vcard) = @_;

    my $exists = $self->load_vcard($user);

    if($exists) {
        $self->{dbh}->do("UPDATE vcard SET vcard = ? WHERE jid = ?", undef, $vcard->as_xml, $user);
    } else {
        $self->{dbh}->do("INSERT INTO vcard (vcard, jid) VALUES (?,?)", undef, $vcard->as_xml, $user);
    }

}

sub check_install_schema {
    my $self = shift;
    my $dbh = $self->{dbh};

    eval {
        $dbh->do(qq{
            CREATE TABLE vcard (
                                 jid   VARCHAR(255) NOT NULL,
                                 vcard TEXT,
                                 UNIQUE (jid)
                                 )})
        };
    if ($@ && $@ !~ /table \w+ already exists/) {
        $logger->logdie("SQL error $@");
    }

}


1;
