package DJabberd::RosterStorage::SQLite;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::RosterStorage';

use DBI;

sub new {
    my $class = shift;
    my $self = $class->SUPER::new();

    my $file = shift;
    warn "file = $file\n";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file","","", { RaiseError => 1, PrintError => 0, AutoCommit => 0 });
    $self->{dbh} = $dbh;
    $self->check_install_schema;
    return $self;
}

sub check_install_schema {
    my $self = shift;
    my $dbh = $self->{dbh};

    eval {
        $dbh->do(qq{
            CREATE TABLE jidmap (
                                 jidid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                                 jid   VARCHAR(255) NOT NULL,
                                 UNIQUE (jid)
                                 )});
        $dbh->do(qq{
            CREATE TABLE roster (
                                 userid        INTEGER PRIMARY KEY REFERENCES jidmap NOT NULL,
                                 contactid     INTEGER REFERENCES jidmap NOT NULL,
                                 name          VARCHAR(255),
                                 subscription  INTEGER NOT NULL REFERENCES substates DEFAULT 0
                                 )});
        $dbh->do(qq{
            CREATE TABLE rostergroup (
                                      groupid       INTEGER PRIMARY KEY REFERENCES jidmap NOT NULL,
                                      userid        INTEGER REFERENCES jidmap NOT NULL,
                                      name          VARCHAR(255),
                                      UNIQUE (userid, name)
                                      )});
        $dbh->do(qq{
            CREATE TABLE groupitem (
                                    groupid       INTEGER REFERENCES jidmap NOT NULL,
                                    contactid     INTEGER REFERENCES jidmap NOT NULL,
                                    PRIMARY KEY (groupid, contactid)
                                    )});

        $dbh->commit;
    };
    if ($@ && $@ !~ /table \w+ already exists/) {
        die "SQL error: $@\n";
    }

    warn "Created them all!\n";


}

sub blocking { 1 }

sub get_roster {
    my ($self, $cb, $conn, $jid) = @_;

}

1;
