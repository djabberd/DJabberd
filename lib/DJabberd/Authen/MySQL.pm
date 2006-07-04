
package DJabberd::Authen::MySQL;
use strict;
use base 'DJabberd::Authen';

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger;
use DBI;
sub log {
    $logger;
}

=head1 NAME

DJabberd::Authen::MySQL - A MySQL authentication module for DJabberd

=head1 VERSION

Version 0.20

=head1 SYNOPSIS

    <VHost mydomain.com>

        [...]

        <Plugin DJabberd::Authen::MySQL>
            DBName               djabberd
            DBHost               127.0.0.1
            DBPort               6723
            DBUsername           dbusername
            DBPassword           dbpassword
            DBTable              user
            DBUsernameColumn     username
            DBPasswordColumn     password
            DBEncryptedPasswords 1
            DBWhere              canjabber = 1
        </Plugin>
    </VHost>

DBName, DBUsername, DBTable, DBUsernameColumn and DBPasswordColumn are required.
Everything else is optional.

DBEncryptedPasswords will cause this plugin to expect password strings generated
by MySQL's PASSWORD() function. Note that this will prevent DJabberd from doing
digest authentication and will thus require clients to send passwords in cleartext.

=cut

sub set_config_dbname {
    my ($self, $dbname) = @_;
    $self->{'mysql_dbname'} = $dbname;
}

sub set_config_dbusername {
    my ($self, $dbusername) = @_;
    $self->{'mysql_dbusername'} = $dbusername;
}

sub set_config_dbpassword {
    my ($self, $dbpassword) = @_;
    $self->{'mysql_dbpassword'} = $dbpassword;
}

sub set_config_dbhost {
    my ($self, $dbhost) = @_;
    $self->{'mysql_dbhost'} = $dbhost;
}

sub set_config_dbport {
    my ($self, $dbport) = @_;
    $self->{'mysql_dbport'} = $dbport;
}

sub set_config_dbtable {
    my ($self, $dbtable) = @_;
    $self->{'mysql_table'} = $dbtable;
}

sub set_config_dbusernamecolumn {
    my ($self, $dbusernamecolumn) = @_;
    $self->{'mysql_usernamecolumn'} = $dbusernamecolumn;
}

sub set_config_dbpasswordcolumn {
    my ($self, $dbpasswordcolumn) = @_;
    $self->{'mysql_passwordcolumn'} = $dbpasswordcolumn;
}

sub set_config_dbencryptedpasswords {
    my ($self, $dbencryptedpassword) = @_;
    $self->{'mysql_encryptedpassword'} = $dbencryptedpassword;
}

sub set_config_dbwhere {
    my ($self, $dbwhere) = @_;
    $self->{'mysql_where'} = $dbwhere;
}

sub finalize {
    my $self = shift;
    my $dsn = "DBI:mysql:database=$self->{'mysql_dbname'}";
    if (defined $self->{'mysql_dbhost'}) { $dsn .= ";host=$self->{'mysql_dbhost'}"; }
    if (defined $self->{'mysql_dbport'}) { $dsn .= ";port=$self->{'mysql_dbport'}"; }
    my $dbh = DBI->connect($dsn, $self->{'mysql_dbusername'}, $self->{'mysql_dbpassword'}, { RaiseError => 1 });
    $self->{'mysql_dbh'} = $dbh;
}

sub can_retrieve_cleartext {
    my $self = shift;
    return $self->{'mysql_encryptedpassword'} ? 0 : 1;
}

sub get_password {
    my ($self, $cb, %args) = @_;

    my $user = $args{'username'};
    my $dbh = $self->{'mysql_dbh'};

    my $sql_username = "SELECT $self->{'mysql_usernamecolumn'}, $self->{'mysql_passwordcolumn'} FROM $self->{'mysql_table'} WHERE $self->{'mysql_usernamecolumn'} = ".$dbh->quote($user);
    my $sql_where = (defined $self->{'mysql_where'} ? " AND $self->{'mysql_where'}" : "");

    my ($username, $password) = $dbh->selectrow_array("$sql_username $sql_where");
    if (defined $username) {
        $logger->debug("Fetched password for '$username'");
        $cb->set($password);
        return;
    }
    $logger->info("Can't fetch password for '$username': user does not exist or did not satisfy WHERE clause");
    $cb->decline;
}

sub check_cleartext {
    my ($self, $cb, %args) = @_;
    my $username = $args{username};
    my $password = $args{password};
    my $conn = $args{conn};
    unless ($username =~ /^\w+$/) {
        $cb->reject;
        return;
    }

    my $dbh = $self->{'mysql_dbh'};
    my $sql_username = "SELECT $self->{'mysql_usernamecolumn'} FROM $self->{'mysql_table'} WHERE $self->{'mysql_usernamecolumn'} = ".$dbh->quote($username);
    my $sql_password = " AND $self->{'mysql_passwordcolumn'} = ".($self->{'mysql_encryptedpassword'} ? "PASSWORD(".$dbh->quote($password).")" : $dbh->quote($password));
    my $sql_where = (defined $self->{'mysql_where'} ? " AND $self->{'mysql_where'}" : "");

    if (defined(($dbh->selectrow_array("$sql_username $sql_password $sql_where"))[0])) {
        $cb->accept;
        $logger->debug("User '$username' authenticated successfully");
        return 1;
    } else {
        $cb->reject();
        if (defined(($dbh->selectrow_array("$sql_username $sql_where"))[0])) { # if user exists
            $logger->info("Auth failed for user '$username': password error");
            return 0;
        } else {
            $logger->info("Auth failed for user '$username': user does not exist or did not satisfy WHERE clause");
            return 1;
        }
    }
}

1;
