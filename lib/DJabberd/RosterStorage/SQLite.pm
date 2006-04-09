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

    my $dbh = $self->{dbh};

    my $roster = DJabberd::Roster->new;

    my $sql = qq{
        SELECT r.contactid, r.name, r.subscription, jmc.jid
        FROM roster r, jidmap jm, jidmap jmc
        WHERE r.userid=jm.jidid and jm.jid=? and jmc.jidid=r.contactid
    };

    # contacts is { contactid -> $row_hashref }
    my $contacts = $dbh->selectall_hashref($sql, "contactid", undef, $jid->as_bare_string);

    foreach my $contact (values %$contacts) {
        my $item =
          DJabberd::RosterItem->new(
                                    jid  => $contact->{jid},
                                    name => $contact->{name},
                                    subscription => 'none', #FIXME: $self->subscription_name($contact->{subscription})
                                    );

        # convert all the values in the hashref into RosterItems
        $contacts->{$contact->{contactid}} = $item;
        $roster->add($item);
    }

    # get all the groups, and add them to the roster items
    $sql = qq{
        SELECT rg.name, gi.contactid
        FROM   rostergroup rg, jidmap j, groupitem gi
        WHERE  gi.groupid=rg.groupid AND rg.userid=j.jidid AND j.jid=?
    };
    my $sth = $dbh->prepare($sql);
    $sth->execute($jid->as_bare_string);
    while (my ($group_name, $contactid) = $sth->fetchrow_array) {
        my $ri = $contacts->{$contactid} or next;
        $ri->add_group($group_name);
    }

    $cb->set_roster($roster);

}

sub set_roster_item {
    my ($self, $cb, $conn, $jid, $ritem) = @_;
    warn "set roster item!\n";
    $cb->declined;
}

sub delete_roster_item {
    my ($self, $cb, $conn, $jid, $ritem) = @_;
    warn "delete roster item!\n";
    $cb->declined;
}

1;
