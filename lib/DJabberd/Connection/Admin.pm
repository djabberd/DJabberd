package DJabberd::Connection::Admin;
use strict;
use warnings;
use base 'Danga::Socket';

use fields qw(buffer server);

sub new {
    my ($class, $sock, $server) = @_;
    my $self = $class->SUPER::new($sock);
    $self->{server} = $server;
    return $self;
}

sub event_read {
    my DJabberd::Connection::Admin $self = shift;

    my $bref = $self->read(20_000);
    return $self->close unless defined $bref;

    $self->{buffer} .= $$bref;

    while ($self->{buffer} =~ s/^(.*?)\r?\n//) {
        my $cmdline = $1;
        $cmdline =~ s/^\s*(\w+)\s*//;
        my $command = $1;
        unless ($command) {
            $self->write("Cannot parse command '$cmdline'");
            return;
        }

        if (my $cref = $self->can("CMD_" . $command)) {
            $cref->($self, $cmdline);
        } else {
            $self->write("Unknown command '$command'");
        }

    }


}

sub CMD_close { $_[0]->close }
sub CMD_quit { $_[0]->close }
sub CMD_exit { $_[0]->close }

*CMD_conns = \&CMD_connections;
sub CMD_connections {
    my ($self, $filter) = @_;

    my $map = Danga::Socket->DescriptorMap;
    my @list;
    foreach (keys %$map) {
        my $obj = $map->{$_};
        next if $filter eq "clients" && ref $obj ne "DJabberd::Connection::ClientIn";
        next if $filter eq "servers" && ref $obj ne "DJabberd::Connection::ServerIn" &&
            ref $obj ne "DJabberd::Connection::ServerOut";
        push @list, $_;
    }
    my $conns = join(' ', @list);
    $self->write($conns);
}

sub CMD_help {
    my $self = shift;
    $self->write($_) foreach split(/\n/, <<EOC);
Available commands:
   version
   help
   list vhosts
   quit
.
EOC
}

sub CMD_list {
    my $self = shift;
    my $type = shift;

    if ($type =~ /^vhosts?/) {
        $self->write($_) foreach keys %{$self->{server}->{vhosts}};
        $self->end;
    } else {
        $self->write("Cannot list '$type'");
    }

}

sub CMD_stats {
    my $self = shift;

    foreach my $name (sort keys %DJabberd::Stats::counter) {
        $self->write("$name\t$DJabberd::Stats::counter{$name}");
    }
    $self->end;
}

sub CMD_version {
    $_[0]->write($DJabberd::VERSION);
}

sub end {
    $_[0]->write('.');
}

sub write {
    my $self = shift;
    my $string = shift;
    $self->SUPER::write($string . "\r\n");
}

sub close {
    my $self = shift;
    $DJabberd::Stats::counter{disconnect}++;
    $self->SUPER::close(@_);
}

1;
