package DJabberd::Connection::Admin;
use strict;
use warnings;
use base 'Danga::Socket';

use fields qw(buffer server);

sub new {
    my ($class, $sock, $server) = @_;
    my $self = $class->SUPER::new($sock);
    $self->{server} = $server;
    $self->write("Welcome to DJabberd $DJabberd::VERSION");
    return $self;
}

sub event_read {
    my DJabberd::Connection::Admin $self = shift;

    my $bref = $self->read(20_000);
    return $self->close unless defined $bref;

    $self->{buffer} .= $$bref;

    while ($self->{buffer} =~ s/^(.*?)\r?\n//) {
        my $cmdline = $1;
        $cmdline =~ s/^\s*(\w+)//;
        my $command = $1;
        unless ($command) {
            $self->write("Cannot parse command '$cmdline'");
            return;
        }
        my @args = grep { $_ } split /\s+/, $cmdline;

        if (my $cref = $self->can("CMD_" . $command)) {
            $cref->($self, @args);
        } else {
            $self->write("Unknown command '$command'");
        }

    }


}

sub CMD_list {
    my $self = shift;
    my $type = shift;

    if ($type =~ /^vhosts?/) {
        $self->write(keys %{$self->{server}->{vhosts}});
    } else {
        $self->write("Cannot list '$type'");
    }

}

sub write {
    my $self = shift;
    my $string = shift;
    $self->SUPER::write($string . "\n");
}




1;
