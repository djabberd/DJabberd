package DJabberd::Connection::Admin;
use strict;
use warnings;
use base 'Danga::Socket';

use fields qw(buffer server handle);

my $has_gladiator  = eval "use Devel::Gladiator; 1;";
my $has_cycle      = eval "use Devel::Cycle; 1;";
my $has_devel_leak = eval "use Devel::Leak; 1;";

my $initial_memory;

sub on_startup {
    $initial_memory ||= get_memory();
}

sub get_memory {
    my $mem;
    if ($^O eq 'linux') {
        my $pid = $$;
        ($mem) = `cat /proc/$pid/status | grep ^VmRSS` =~ /(\d+)/;
    } else {
        $mem = 0;
    }
    return $mem;
}

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
        my $line = $1;
        $self->process_line($line);
    }
}

sub process_line {
    my DJabberd::Connection::Admin $self = shift;
    my $line = shift;
    return unless $line =~ /\S/;

    $line =~ s/^\s*(\w+)\s*//;
    my $command = $1;
    unless ($command) {
        $self->write("Cannot parse command '$line'");
        return;
    }

    if (my $cref = DJabberd::Connection::Admin->can("CMD_" . $command)) {
        $cref->($self, $line);
    } else {
        $self->write("Unknown command '$command'");
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

sub CMD_latency_log {
   my $self = shift;
    foreach my $le (@DJabberd::Stats::stanza_process_latency_log) {
        next unless defined $le;
        $self->write("$le->[0]\t$le->[1]");
    }
   $self->end;
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

    my $conns       = keys %{ Danga::Socket->DescriptorMap};
    my $conns_quick = $DJabberd::Stats::counter{connect} - $DJabberd::Stats::counter{disconnect};

    my $users = 0;
    DJabberd->foreach_vhost(sub {
        my $vhost = shift;
        $users += keys %{$vhost->{jid2sock}};
    });

    $self->write("connections\t$conns\tconnections");
    $self->write("users\t$users\tusers");
    $self->write("connections_quickcalc\t$conns_quick\tconnections");

    my $mem      = get_memory();
    my $user_mem = $mem - $initial_memory;

    $self->write("mem_total\t$mem\tkB");
    $self->write("mem_connections\t$user_mem\tkB");
    $self->write("mem_per_connection\t". ($user_mem / ($conns || 1) ) . "\tkB/conn");
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

sub _in_sub_process {
    my $code = shift;
    my $rand = rand();
    my $file = ".tmp.$$.$rand.answer";

    my $cpid = fork;
    if ($cpid) {
        wait;
        open (my $fh, $file);
        my $data = do { local $/; <$fh> };
        my $res = eval { Storable::thaw($data); };
        unlink $file;
        return $res;
    }

    my $res = $code->();
    if (open (my $fh, ">$file.writing")) {
        print $fh Storable::nfreeze($res);
        close $fh;
        rename "$file.writing", $file;
        exit 0;
    }
}

sub arena_ref_counts {
    my $all = Devel::Gladiator::walk_arena();
    my %ct;
    foreach my $it (@$all) {
        $ct{ref $it}++;
        if (ref $it eq "REF") {
            $ct{"REF-" . ref $$it}++;
        }
        elsif (ref $it eq "DJabberd::IQ") {
            $ct{"DJabberd::IQ-" . $it->signature}++;
        }
        elsif (ref $it eq "Gearman::Task") {
            $ct{"Gearman::Task-func:$it->{func}"}++;
        }
        elsif (ref $it eq "DJabberd::Callback") {
            $ct{"DJabberd::Callback-" . $it->{_phase}}++ if $it->{_phase};
        }
    }
    $all = undef;
    return \%ct;
}

my %last_gladiator;
sub CMD_gladiator {
    my ($self, $cmd) = @_;

    unless ($has_gladiator) {
        $self->end;
        return;
    }

    $cmd ||= "lite";

    my $ct = _in_sub_process(sub { arena_ref_counts() });
    my $ret;
    $ret .= "ARENA COUNTS:\n";
    foreach my $k (sort {$ct->{$b} <=> $ct->{$a}} keys %$ct) {
        my $delta = $ct->{$k} - ($last_gladiator{$k} || 0);
        $last_gladiator{$k} = $ct->{$k};
        if ($cmd eq "delta") {
            next unless $delta;
        } elsif ($cmd eq "lite") {
            next if $k =~ /^REF-/;
            next if $k =~ /^DJabberd::AnonSubFrom::lib_DJabberd_RosterStorage/;
            next if $k =~ /log4perl/i;
        } else {
            next unless $ct->{$k} > 1 || $cmd eq "all";
        }
        $ret .= sprintf(" %4d %-4d $k\n", $ct->{$k}, $delta);
    }

    $self->write($ret);
    $self->end;
}

sub CMD_cycle {
    my $self = shift;

    unless ($has_gladiator && $has_cycle) {
        $self->end;
        return;
    }

    my $array = Devel::Gladiator::walk_arena();
    #my @list = grep { ref($_) =~ /^DJabberd::VHost|DJabberd::Connection::ClientIn|DJabberd::AnonSubFrom/ } @$array;
    my @list = grep { ref($_) =~ /^DJabberd|Gearman|CODE/ } @$array;
    $array = undef;

    use Data::Dumper;
#    my $flist = \%DJabberd::Connection::ClientIn::FIELDS;
#    foreach my $k (sort { $flist->{$a} <=> $flist->{$b} } keys %$flist) {
#        printf STDERR " %4d %s\n", $flist->{$k}, $k;
#    }
    find_cycle(\@list);
    $self->end;

}

sub CMD_fields {
    my ($self, $arg) = @_;
    my $flist = eval "\\%${arg}::FIELDS";
    foreach my $k (sort { $flist->{$a} <=> $flist->{$b} } keys %$flist) {
        printf STDERR " %4d %s\n", $flist->{$k}, $k;
    }
    $self->end;
}

sub CMD_note_arena {
    my ($self, $arg) = @_;
    return unless $has_devel_leak;
    $self->{handle} = 1;
    Devel::Leak::NoteSV($self->{handle});
    $self->end;
}

sub CMD_check_arena {
    my ($self, $arg) = @_;
    return unless $has_devel_leak;
    Devel::Leak::CheckSV($self->{handle});
    $self->end;
}

sub CMD_reload {
    my $self = shift;
    delete $INC{"DJabberd/Connection/Admin.pm"};
    no warnings 'redefine';
    my $rv = eval "use DJabberd::Connection::Admin; 1;";
    if ($rv) {
        $self->write("OK");
    } else {
        $self->write("ERROR: $@");
    }
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
    $DJabberd::Stats::counter{disconnect}++ unless $self->{closed};
    $self->SUPER::close(@_);
}

1;
