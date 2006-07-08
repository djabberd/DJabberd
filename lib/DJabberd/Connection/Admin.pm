package DJabberd::Connection::Admin;
use strict;
use warnings;
use base 'Danga::Socket';

use fields qw(buffer server);

my $has_gladiator = eval "use Devel::Gladiator; 1;";

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

sub CMD_latency {
    my $self = shift;
    my %hist;
    my @buckets = (
                   '0.0005',
                   '0.001', '0.002', '0.005',
                   '0.01',  '0.02',  '0.05',
                   '0.1',   '0.2',
                   '1.0', '2.0', '10.0',
                   );
    foreach my $td (@DJabberd::Stats::stanza_process_latency) {
        next unless defined $td;
        foreach my $bk (@buckets) {
            if ($td < $bk) {
                $hist{$bk}++;
                last;
            }
        }
    }
    foreach my $bk (@buckets) {
        next unless $hist{$bk};
        $self->write("-$bk\t$hist{$bk}");
    }
    $self->end;
}

sub CMD_help {
    my $self = shift;
    $self->write($_) foreach split(/\n/, <<EOC);
Available commands:
   version
   help
   list vhosts
   quit
   connections
   conns
   conns servers
   conns clients
   latency
   users
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

    my $connections = $DJabberd::Stats::counter{connect} - $DJabberd::Stats::counter{disconnect};
    $self->write("connections\t$connections\tconnections");
    if ($^O eq 'linux') {
        my ($mem) = `cat /proc/\`pidof -x djabberd\`/status | grep ^VmRSS` =~ /(\d+)/;
        $self->write("mem_total\t$mem\tkB");
        $self->write("mem_per_connection\t". ($mem / ($connections || 1) ) . "\tkB/conn");
    }

    $self->end;
}

sub CMD_counters {
    my $self = shift;

    foreach my $name (sort keys %DJabberd::Stats::counter) {
        $self->write("$name\t$DJabberd::Stats::counter{$name}");
    }
    $self->end;
}

sub CMD_users {
    my $self = shift;

    DJabberd->foreach_vhost(sub {
        my $vhost = shift;
        $self->write("$vhost->{server_name}");
        foreach my $jid (keys %{$vhost->{jid2sock}}) {
            $self->write("\t$jid");
        }
    });
    $self->end;
}

sub CMD_version {
    $_[0]->write($DJabberd::VERSION);
}

my %last_gladiator;
sub CMD_gladiator {
    my ($self, $cmd) = @_;

    unless ($has_gladiator) {
        $self->end;
        return;
    }

    my $ct = Devel::Gladiator->arena_ref_counts();
    my $ret;
    $ret .= "ARENA COUNTS:\n";
    foreach my $k (sort {$ct->{$b} <=> $ct->{$a}} keys %$ct) {
        my $delta = $ct->{$k} - $last_gladiator{$k};
        if ($cmd eq "delta") {
            next unless $delta;
        } else {
            next unless $ct->{$k} > 1 || $cmd eq "all";
        }
        $ret .= sprintf(" %4d %-4d $k\n", $ct->{$k}, $delta);
        $last_gladiator{$k} = $ct->{$k};
    }

    $self->write($ret);
    $self->end;
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
