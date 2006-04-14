package DJabberd::RosterStorage::SQLite;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::RosterStorage';

use DBI;

use vars qw($_respect_subscription);

sub new {
    my $class = shift;
    my $self = $class->SUPER::new();

    my $file = shift;
    warn "file = $file\n";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file","","", { RaiseError => 1, PrintError => 0, AutoCommit => 1 });
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
                                 userid        INTEGER REFERENCES jidmap NOT NULL,
                                 contactid     INTEGER REFERENCES jidmap NOT NULL,
                                 name          VARCHAR(255),
                                 subscription  INTEGER NOT NULL REFERENCES substates DEFAULT 0,
                                 PRIMARY KEY (userid, contactid)
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
    my ($self, $cb, $jid) = @_;

    warn "Getting roster for $jid.\n";

    my $dbh = $self->{dbh};

    my $roster = DJabberd::Roster->new;

    my $sql = qq{
        SELECT r.contactid, r.name, r.subscription, jmc.jid
        FROM roster r, jidmap jm, jidmap jmc
        WHERE r.userid=jm.jidid and jm.jid=? and jmc.jidid=r.contactid
    };

    # contacts is { contactid -> $row_hashref }
    my $contacts = eval {
        $dbh->selectall_hashref($sql, "contactid", undef, $jid->as_bare_string);
    };
    die "Failed to load roster: $@\n" if $@;
    warn "  ... got contacts.\n";

    foreach my $contact (values %$contacts) {
        my $item =
          DJabberd::RosterItem->new(
                                    jid          => $contact->{jid},
                                    name         => $contact->{name},
                                    subscription => DJabberd::Subscription->from_bitmask($contact->{subscription}),
                                    );

        # convert all the values in the hashref into RosterItems
        $contacts->{$contact->{contactid}} = $item;
        $roster->add($item);
    }

    # get all the groups, and add them to the roster items
    eval {
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
    };
    die "Failed to load roster groups: $@\n" if $@;
    warn "  ... got groups, calling set_roster..\n";
    $cb->set_roster($roster);

}

# to be called outside of a transaction, in auto-commit mode
sub _jidid_alloc {
    my ($self, $jid) = @_;
    my $dbh  = $self->{dbh};
    my $jids = $jid->as_bare_string;
    my $id   = eval {
        $dbh->selectrow_array("SELECT jidid FROM jidmap WHERE jid=?",
                              undef, $jids);
    };
    die "Failed to select from jidmap: $@\n" if $@;
    return $id if $id;

    eval {
        $dbh->do("INSERT INTO jidmap (jidid, jid) VALUES (NULL, ?)",
                 undef, $jids);
    };
    die "_jidid_alloc failed: $@" if $@;

    $id = $dbh->last_insert_id(undef, undef, "jidmap", "jidid")
        or die "Failed to allocate a number in _jidid_alloc";

    return $id;
}

# to be called outside of a transaction, in auto-commit mode
sub _groupid_alloc {
    my ($self, $userid, $name) = @_;
    my $dbh  = $self->{dbh};
    my $id   = eval {
        $dbh->selectrow_array("SELECT groupid FROM rostergroup WHERE userid=? AND name=?",
                              undef, $userid, $name);
    };
    die "Failed to select from groupid: $@\n" if $@;
    return $id if $id;

    eval {
        $dbh->do("INSERT INTO rostergroup (groupid, userid, name) VALUES (NULL, ?, ?)",
                 undef, $userid, $name);
    };
    die "_groupid_alloc failed: $@" if $@;

    $id = $dbh->last_insert_id(undef, undef, "rostergroup", "groupid")
        or die "Failed to allocate a number in _groupid_alloc";

    return $id;
}

sub set_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    local $_respect_subscription = 1;
    warn "set roster item!\n";
    $self->addupdate_roster_item($cb, $jid, $ritem);
}

sub addupdate_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    warn "addupdate roster item!\n";
    my $dbh  = $self->{dbh};

    my $userid    = $self->_jidid_alloc($jid);
    my $contactid = $self->_jidid_alloc($ritem->jid);

    unless ($userid && $contactid) {
        $cb->error("no userid and contactid");
        return;
    }

    $dbh->begin_work or
        die "Failed to begin work";

    my $fail = sub {
        my $reason = shift;
        die "Failing to addupdate: $reason";
        $dbh->rollback;
        $cb->error($reason);
        return;
    };

    my $exists = $dbh->selectrow_array("SELECT COUNT(*) FROM roster WHERE userid=? AND contactid=?",
                                       undef, $userid, $contactid);


    my %in_group;  # groupname -> 1

    if ($exists) {
        my @groups = $self->_groups_of_contactid($userid, $contactid);
        my %to_del; # groupname -> groupid
        foreach my $g (@groups) {
            $in_group{$g->[1]} = 1;
            $to_del  {$g->[1]} = $g->[0];
        }
        foreach my $gname ($ritem->groups) {
            delete $to_del{$gname};
        }
        if (my $in = join(",", values %to_del)) {
            $dbh->do("DELETE FROM groupitem WHERE groupid IN ($in) AND contactid=?",
                     undef, $contactid);
        }

        # by default, don't change subscription, unless we're being called
        # via set_roster_item.
        my $sub_value = "subscription";
        if ($_respect_subscription) {
            $sub_value = $ritem->subscription->as_bitmask;
            warn " sub_value = $sub_value\n";
        }

        my $sql  = "UPDATE roster SET name=?, subscription=$sub_value WHERE userid=? AND contactid=?";
        my @args = ($ritem->name, $userid, $contactid);
        $dbh->do($sql, undef, @args);
    } else {
        $dbh->do("INSERT INTO roster (userid, contactid, name, subscription) ".
                 "VALUES (?,?,?,?)", undef,
                 $userid, $contactid, $ritem->name, $ritem->subscription->as_bitmask)
    }

    # add to groups
    foreach my $gname ($ritem->groups) {
        next if $in_group{$gname};  # already in this group, skip
        my $gid = $self->_groupid_alloc($userid, $gname);
        $dbh->do("INSERT OR IGNORE INTO groupitem (groupid, contactid) VALUES (?,?)",
                 undef, $gid, $contactid);
    }

    $dbh->commit
        or return $fail->();

    $cb->done;
}

# returns ([groupid, groupname], ...)
sub _groups_of_contactid {
    my ($self, $userid, $contactid) = @_;
    my @ret;
    my $sql = qq{
        SELECT rg.groupid, rg.name
            FROM   rostergroup rg, groupitem gi
            WHERE  rg.userid=? AND gi.groupid=rg.groupid AND gi.contactid=?
        };
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($userid, $contactid);
    while (my ($gid, $name) = $sth->fetchrow_array) {
        push @ret, [$gid, $name];
    }
    return @ret;
}

sub delete_roster_item {
    my ($self, $cb, $jid, $ritem) = @_;
    warn "delete roster item!\n";

    my $dbh  = $self->{dbh};

    my $userid    = $self->_jidid_alloc($jid);
    my $contactid = $self->_jidid_alloc($ritem->jid);

    unless ($userid && $contactid) {
        $cb->error("no userid/contactid in delete");
        return;
    }

    $dbh->begin_work;

    my $fail = sub {
        $dbh->rollback;
        $cb->error;
        return;
    };

    my @groups = $self->_groups_of_contactid($userid, $contactid);

    if (my $in = join(",", map { $_->[0] } @groups)) {
        $dbh->do("DELETE FROM groupitem WHERE groupid IN ($in) AND contactid=?",
                 undef, $contactid);
    }

    $dbh->do("DELETE FROM roster WHERE userid=? AND contactid=?",
             undef, $userid, $contactid)
        or return $fail->();

    $dbh->commit or $fail->();

    $cb->done;
}

sub load_roster_item {
    my ($self, $jid, $contact_jid, $cb) = @_;

    my $dbh  = $self->{dbh};

    my $userid    = $self->_jidid_alloc($jid);
    my $contactid = $self->_jidid_alloc($contact_jid);
    unless ($userid && $contactid) {
        $cb->error("no userid/contactid in load");
        return;
    }

    my $row = $dbh->selectrow_hashref("SELECT name, subscription FROM roster ".
                                      "WHERE userid=? AND contactid=?",
                                      undef, $userid, $contactid);
    unless ($row) {
        $cb->set(undef);
        return;
    }

    my $item =
        DJabberd::RosterItem->new(
                                  jid          => $contact_jid,,
                                  name         => $row->{name},
                                  subscription => DJabberd::Subscription->from_bitmask($row->{subscription}),
                                  );
    foreach my $ga ($self->_groups_of_contactid($userid, $contactid)) {
        $item->add_group($ga->[1]);
    }

    $cb->set($item);
    return;
}


1;
