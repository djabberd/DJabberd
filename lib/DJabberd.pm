#!/usr/bin/perl

use strict;
use Carp;
use Danga::Socket 1.51;
use IO::Socket::INET6;
use IO::Socket::UNIX;
use POSIX ();

use DJabberd::VHost;
use DJabberd::Callback;
use Scalar::Util;
use DJabberd::HookDocs;
use DJabberd::Connection;
use DJabberd::Connection::ServerIn;
use DJabberd::Connection::ClientIn;
use DJabberd::Connection::ClusterIn;
use DJabberd::Connection::OldSSLClientIn;
use DJabberd::Connection::Admin;

use DJabberd::Stanza::StartTLS;
use DJabberd::Stanza::SASL;
use DJabberd::Stanza::StreamFeatures;
use DJabberd::Stanza::DialbackVerify;
use DJabberd::Stanza::DialbackResult;
use DJabberd::JID;
use DJabberd::IQ;
use DJabberd::Message;
use DJabberd::Presence;
use DJabberd::StreamVersion;
use DJabberd::Log;

use DJabberd::Delivery::Local;
use DJabberd::Delivery::S2S;
use DJabberd::PresenceChecker::Local;

use DJabberd::Stats;

package DJabberd;
use strict;
use Socket qw(IPPROTO_TCP TCP_NODELAY SOL_SOCKET SOCK_STREAM);
use Carp qw(croak);
use DJabberd::Util qw(tsub as_bool as_num as_abs_path as_bind_addr);

our $VERSION = '0.85';

our $logger = DJabberd::Log->get_logger();
our $hook_logger = DJabberd::Log->get_logger("DJabberd::Hook");

our %server;

$SIG{USR2} = sub { Carp::cluck("USR2") };

sub new {
    my ($class, %opts) = @_;
    
    my $s2s_port = delete $opts{s2s_port};
    my $c2s_port = delete $opts{c2s_port};
    my $ssl_port = delete $opts{ssl_port};

    my $self = {
        'daemonize'   => delete $opts{daemonize},
        'old_ssl'     => delete $opts{old_ssl},
        'vhosts'      => {},
        'fake_peers'  => {}, # for s2s testing.  $hostname => "ip:port"
        'share_parsers' => 1,
        'monitor_host' => {},
    };
    
    # if they set s2s_port to explicitly 0, it's disabled for all vhosts
    # but not setting it means 5269 still listens, if vhosts are configured
    # for s2s.
    # {=serverportnumber}
    if(defined($s2s_port) && ref($s2s_port) eq 'HASH') { # hashref
        $self->{s2s_port} = $s2s_port;
    } elsif($s2s_port && !ref($s2s_port)) { # scalar
        $self->{s2s_port}->{$s2s_port}++;
    } elsif(!defined($s2s_port)) { # default
        $self->{s2s_port}->{5269}++;
    }
    
    if(defined($c2s_port) && ref($c2s_port) eq 'HASH') { # hashref
        $self->{c2s_port} = $c2s_port;
    } elsif($c2s_port && !ref($c2s_port)) { # scalar
        $self->{c2s_port}->{$c2s_port}++;
    } else { # default
        $self->{c2s_port}->{5222}++;
    }
    
    if(defined($ssl_port) && ref($ssl_port) eq 'HASH') {
        $self->{ssl_port} = $ssl_port;
    } elsif($ssl_port && !ref($ssl_port)) { # scalar
        $self->{ssl_port}->{$ssl_port}++;
    }

    croak("Unknown server parameters: " . join(", ", keys %opts)) if %opts;

    bless $self, $class;
    $server{$self} = $self;
    Scalar::Util::weaken($server{$self});

    return $self;
}

sub DESTROY {
    delete $server{$_[0]};
}

# class method
sub foreach_vhost {
    my (undef, $cb) = @_;
    foreach my $server (values %DJabberd::server) {
        foreach my $vhost (values %{$server->{vhosts}}) {
            $cb->($vhost);
        }
    }
}

sub share_parsers { $_[0]{share_parsers} };

sub set_config_shareparsers {
    my ($self, $val) = @_;
    $self->{share_parsers} = as_bool($val);
}

sub set_config_declaremonitor {
    my ($self, $val) = @_;
    $self->{monitor_host}{$val} = 1;
}

# mimicing Apache's SSLCertificateKeyFile config
sub set_config_sslcertificatekeyfile {
    my ($self, $val) = @_;
    $self->{ssl_private_key_file} = as_abs_path($val);
}

# mimicing Apache's SSLCertificateFile
sub set_config_sslcertificatefile {
    my ($self, $val) = @_;
    $self->{ssl_cert_file} = as_abs_path($val);
}

# mimicing Apache's SSLCertificateChainFile
sub set_config_sslcertificatechainfile {
    my ($self, $val) = @_;
    $self->{ssl_cert_chain_file} = as_abs_path($val);
}

sub ssl_private_key_file { return $_[0]{ssl_private_key_file} }
sub ssl_cert_file        { return $_[0]{ssl_cert_file}        }
sub ssl_cert_chain_file  { return $_[0]{ssl_cert_chain_file}  }

sub set_config_oldssl {
    my ($self, $val) = @_;
    $self->{old_ssl} = as_bool($val);
}

sub add_config_sslport {
    my ($self, $val) = @_;
    $self->{ssl_port}->{as_bind_addr($val)}++;
}

sub set_config_sslport {
    my ($self, $val) = @_;
    $self->{ssl_port} = {
        as_bind_addr($val) => 1,
    };
}

sub add_config_unixdomainsocket {
    my ($self, $val) = @_;
    $self->{unixdomainsocket}->{$val}++;
}

sub set_config_unixdomainsocket {
    my ($self, $val) = @_;
    $self->{unixdomainsocket} = {
        $val => 1,
    };
}

sub set_config_clientport {
    my ($self, $val) = @_;
    
    $self->{c2s_port} = {
        as_bind_addr($val) => 1,
    };
}

sub add_config_clientport {
    my ($self, $val) = @_;
    # necessary because the default in the constructor
    # will be 5222 and subsequent binds would fail
    if($self->{c2s_port} && ref($self->{c2s_port}) && exists $self->{c2s_port}->{5222}) {
        delete $self->{c2s_port}->{5222};
    }
    $self->{c2s_port}->{as_bind_addr($val)}++;
}

sub set_config_serverport {
    my ($self, $val) = @_;
    
    $self->{s2s_port} = {
        as_bind_addr($val) => 1,
    };
}

sub add_config_serverport {
    my ($self, $val) = @_;
    # necessary because the default in the constructor
    # will be 5269 and subsequent binds would fail
    if($self->{s2s_port} && ref($self->{s2s_port}) && exists $self->{s2s_port}->{5269}) {
        delete $self->{s2s_port}->{5269};
    }
    $self->{s2s_port}->{as_bind_addr($val)}++;
}

sub set_config_adminport {
    my ($self, $val) = @_;
    $self->{admin_port} = {
        as_bind_addr($val) => 1,
    };
}

sub add_config_adminport {
    my ($self, $val) = @_;
    $self->{admin_port}->{as_bind_addr($val)}++;
}

sub set_config_intradomainlisten {
    my ($self, $val) = @_;
    $self->{cluster_listen} = {
        $val => 1,
    };
}

sub add_config_intradomainlisten {
    my ($self, $val) = @_;
    $self->{cluster_listen}->{$val}++;
}

sub set_config_pidfile {
    my ($self, $val) = @_;
    $self->{pid_file} = $val;
}

our %fake_peers;
sub set_fake_s2s_peer {
    my ($self, $host, $ipendpt) = @_;
    $fake_peers{$host} = $ipendpt;
}

sub fake_s2s_peer {
    my ($self, $host) = @_;
    return $fake_peers{$host};
}

sub set_config_casesensitive {
    my ($self, $val) = @_;
    $DJabberd::JID::CASE_SENSITIVE = as_bool($val);
}

sub add_vhost {
    my ($self, $vhost) = @_;
    my $sname = lc $vhost->name;
    if (my $existing = $self->{vhosts}{$sname}) {
        croak("Can't set vhost with name '$sname'.  Already exists in this server.")
            if $existing != $vhost;
    }
    if ($vhost->server && $vhost->server != $self) {
        croak("Vhost already has a server.");
    }

    $vhost->setup_default_plugins;

    $self->{vhosts}{$sname} = $vhost;
    $vhost->set_server($self);
}

# works as Server method or class method.
sub lookup_vhost {
    my ($self, $hostname) = @_;

    # look at all server objects in process
    unless (ref $self) {
        foreach my $server (values %DJabberd::server) {
            my $vh = $server->lookup_vhost($hostname);
            return $vh if $vh;
        }
        return 0;
    }

    # method on server object
    foreach my $vhost (values %{$self->{vhosts}}) {
        return $vhost
            if ($vhost->handles_domain($hostname));
    }
    return 0;
}

# return the version of the spec we implement
sub spec_version {
    my $self = shift;
    return $self->{_spec_version} ||= DJabberd::StreamVersion->new("1.0");
}


my %obj_source;   # refaddr -> file/linenumber
my %obj_living;   # file/linenumber -> ct
use Scalar::Util qw(refaddr weaken);
use Data::Dumper;
sub dump_obj_stats {
    print Dumper(\%obj_living);
    my %class_ct;
    foreach (values %obj_source) {
        $class_ct{ref($_->[1])}++;
    }
    print Dumper(\%class_ct);
}


sub track_new_obj {
    return unless $ENV{TRACKOBJ};

    my ($class, $obj) = @_;
    my $i = 0;
    my $fileline;
    while (!$fileline) {
        $i++;
        my ($pkg, $filename, $line, $subname) = caller($i);
        next if $subname eq "new";
        $fileline = "$filename/$line";
    }
    my $addr = refaddr($obj);
    warn "New object $obj -- $fileline\n" if $ENV{TRACKOBJ};
    $obj_source{$addr} = [$fileline, $obj];
    weaken($obj_source{$addr}[1]);

    $obj_living{$fileline}++;
    dump_obj_stats() if $ENV{TRACKOBJ};
}

sub track_destroyed_obj {
    return unless $ENV{TRACKOBJ};

    my ($class, $obj) = @_;
    my $addr = refaddr($obj);
    my $fileline = $obj_source{$addr}->[0] or die "Where did $obj come from?";
    delete $obj_source{$addr};
    warn "Destroyed object $obj -- $fileline\n" if $ENV{TRACKOBJ};
    $obj_living{$fileline}--;
    dump_obj_stats() if $ENV{TRACKOBJ};
}

sub debug {
    my $self = shift;
    return unless $self->{debug};
    printf STDERR @_;
}

sub run {
    my $self = shift;
    daemonize() if $self->{daemonize};
    local $SIG{'PIPE'} = "IGNORE";  # handled manually
    if ($self->{pid_file}) {
        $logger->debug("Logging PID to file $self->{pid_file}");
        open(PIDFILE,'>',$self->{pid_file}) or $logger->logdie("Can't open pidfile $self->{pid_file} for writing");
        print PIDFILE "$$\n";
        close(PIDFILE);
    }
    $self->start_c2s_server();

    # {=s2soptional}
    $self->start_s2s_server() if $self->{s2s_port};

    $self->start_cluster_server() if $self->{cluster_listen};

    $self->_start_servers($self->{admin_port}, "DJabberd::Connection::Admin") if $self->{admin_port};

    DJabberd::Connection::Admin->on_startup;
    Danga::Socket->EventLoop();
    unlink($self->{pid_file}) if (-f $self->{pid_file});
}

# this will start up one server for each defined listening socket
sub _start_servers {
    my ($self, $localaddrs, $class) = @_;
    
    my @addrs;
    if(ref($localaddrs) eq 'HASH') {
        @addrs = sort keys %$localaddrs;
    } else {
        @addrs = ($localaddrs);
    }
    
    foreach my $localaddr (@addrs) {
        $self->_start_server($localaddr, $class);
    }
}

sub _start_server {
    my ($self, $localaddr, $class) = @_;

    # establish SERVER socket, bind and listen.
    my $server;
    my $not_tcp = 0;
    if ($localaddr =~ m!^/!) {
        $not_tcp = 1;
        $server = IO::Socket::UNIX->new(Type   => SOCK_STREAM,
                                        Local  => $localaddr,
                                        Listen => 10)
            or $logger->logdie("Error creating unix domain socket: $@\n");
    } else {
        # assume it's a port if there's no number after the (last) colon
        unless ($localaddr =~ /:\d+$/) {
            $localaddr = '[::]:'.$localaddr;
        }

        $logger->debug("Opening TCP listen socket on $localaddr");

        $server = IO::Socket::INET6->new(LocalAddr => $localaddr,
                                        Type      => SOCK_STREAM,
                                        Proto     => IPPROTO_TCP,
                                        Reuse     => 1,
                                        Listen    => 10 )
            or $logger->logdie("Error creating socket for $localaddr: $@\n");

        my $success = $server->blocking(0);

        unless (defined($success)) {
            if ($^O eq 'MSWin32') {
                # On Windows, we have to do this a bit differently
                my $do = 1;
                ioctl($server, 0x8004667E, \$do) or $logger->warn("Failed to make socket non-blocking: $!");
            }
            else {
                $logger->warn("Failed to make socket non-blocking: $!")
            }
        }
    }

    # Not sure if I'm crazy or not, but I can't see in strace where/how
    # Perl 5.6 sets blocking to 0 without this.  In Perl 5.8, IO::Socket::INET
    # obviously sets it from watching strace.
    IO::Handle::blocking($server, 0);

    my $accept_handler = sub {
        local *__ANON__ = " Accept handler in ". __FILE__ ." on line ". __LINE__;

        my $csock = $server->accept;
        return unless $csock;

        $self->debug("Listen child making a DJabberd::Connection for %d.\n", fileno($csock));

        IO::Handle::blocking($csock, 0);
        unless ($not_tcp) {
            setsockopt($csock, IPPROTO_TCP, TCP_NODELAY, pack("l", 1)) or die;
        }

        if (my $client = eval { $class->new($csock, $self) }) {
            $DJabberd::Stats::counter{connect}++;
            $client->watch_read(1);
            return;
        } else {
            $logger->error("Error creating new $class: $@");
        }
    };

    Danga::Socket->AddOtherFds(fileno($server) => $accept_handler);
}

sub start_c2s_server {
    my $self = shift;
    $self->_start_servers($self->{c2s_port},
                         "DJabberd::Connection::ClientIn");

    # usually setting OldSSL 1 in the config file
    # the server would magically listen on port 5223
    # however this conflicts a litte with the new
    # multi socket capabilities so add a new keyword
    # SSLPort which works like e.g. ClientPort and
    # have a fallback for old configs here
    if ($self->{old_ssl} || $self->{ssl_port}) {
        if(!$self->{ssl_port}) {
            $self->{ssl_port}->{5223}++;
        }
        $self->_start_servers($self->{ssl_port}, "DJabberd::Connection::OldSSLClientIn");
    }

    if ($self->{unixdomainsocket}) {
        $self->_start_servers($self->{unixdomainsocket}, "DJabberd::Connection::ClientIn");
    }
}

sub start_s2s_server {
    my $self = shift;
    $self->_start_servers($self->{s2s_port},
                         "DJabberd::Connection::ServerIn");
}

sub start_cluster_server {
    my $self = shift;
    $self->_start_servers($self->{cluster_listen},
                         "DJabberd::Connection::ClusterIn");
}

sub start_simple_server {
    my ($self, $port) = @_;
    eval "use DJabberd::Connection::SimpleIn; 1"
        or die "Failed to load DJabberd::Connection::SimpleIn: $@\n";
    $self->_start_server($port, "DJabberd::Connection::SimpleIn");
}

sub is_monitor_host {
    my ($self, $host) = @_;
    return $self->{monitor_host}{$host};
}

sub load_config {
    my ($self, $arg) = @_;
    if (ref $arg eq "SCALAR") {
        $self->_load_config_ref($arg);
    } else {
        open (my $fh, $arg) or die "Couldn't open config file '$arg': $!\n";
        my $slurp = do { local $/; <$fh>; };
        $self->_load_config_ref(\$slurp);
    }
}

sub _load_config_ref {
    my ($self, $configref) = @_;
    my $linenum = 0;
    my $vhost;  # current vhost in scope
    my $plugin; # current plugin in scope
    my @vhost_stack = ();

    my $expand_var = sub {
        my ($type, $key) = @_;
        $type = uc $type;

        if ($type eq "ENV") {
            # expands ${ENV:KEY} on a line into $ENV{'KEY'} or dies if not defined
            my $val = $ENV{$key};
            die "Undefined environment variable '$key'\n" unless defined $val;
            return $val;
        }
        die "Unknown variable type '$type'\n";
    };

    foreach my $line (split(/\n/, $$configref)) {
        $linenum++;

        $line =~ s/^\s+//;
        next if $line =~ /^\#/;
        $line =~ s/\s+$//;
        next unless $line =~ /\S/;

        eval {
            # expand environment variables
            $line =~ s/\$\{(\w+):(\w+)\}/$expand_var->($1, $2)/eg;

            if ($line =~ /^(\w+)\s+(.+)/) {
                my $pkey = $1;
                my $key = lc $1;
                my $val = $2;
                my $inv = $plugin || $vhost || $self;
                my $meth = "add_config_$key";
                if ($inv->can($meth)) {
                    $inv->$meth($val);
                    return;
                }
                $meth = "set_config_$key";
                if ($inv->can($meth)) {
                    $inv->$meth($val);
                    return;
                }
                $meth = "set_config__option";
                if ($inv->can($meth)) {
                    $inv->$meth($key, $val);
                    return;
                }

                die "Unknown option '$pkey'\n";
            }
            if ($line =~ /<VHost\s+(\S+?)>/i) {
                die "Can't configure a vhost in a vhost\n" if $vhost;
                $vhost = DJabberd::VHost->new(server_name => $1);
                $vhost->set_server($self);
                return;
            }
            if ($line =~ m!</VHost>!i) {
                die "Can't end a not-open vhost\n" unless $vhost;
                die "Can't end a vhost with an open plugin\n" if $plugin;
                die "Can't end a vhost with an open subdomain\n" if @vhost_stack;
                $self->add_vhost($vhost);
                $vhost = undef;
                return;
            }
            if ($line =~ /<Subdomain\s+(\S+?)>/i) {
                die "Subdomain blocks can only inside VHost\n" unless $vhost;
                my $subdomain_name = $1.".".$vhost->server_name;

                my $old_vhost = $vhost;
                push @vhost_stack, $old_vhost;

                $vhost = DJabberd::VHost->new(server_name => $subdomain_name);
                $vhost->set_server($self);

                # Automatically add the LocalVHosts delivery plugin so that these
                # VHosts can talk to one another without S2S.
                my $loaded = eval "use DJabberd::Delivery::LocalVHosts; 1;";
                die "Failed to load LocalVHosts delivery plugin for subdomain" unless $loaded;

                my $ld1 = DJabberd::Delivery::LocalVHosts->new(allowvhost => $subdomain_name);
                my $ld2 = DJabberd::Delivery::LocalVHosts->new(allowvhost => $old_vhost->server_name);
                $old_vhost->add_plugin($ld1);
                $vhost->add_plugin($ld2);

                return;
            }
            if ($line =~ m!</Subdomain>!i) {
                die "Extraneous subdomain end\n" unless @vhost_stack;
                $self->add_vhost($vhost);
                $vhost = pop @vhost_stack;
                return;
            }
            my $close_plugin = sub {
                die "Can't end a not-open plugin\n" unless $plugin;
                $plugin->finalize;
                $vhost->add_plugin($plugin);
                $plugin = undef;
            };

            if ($line =~ /<Plugin\s+([\w:]+?)(\s*\/)?>/i) {
                my $class = $1;
                my $immediate_close = $2;
                die "Can't configure a plugin outside of a vhost config vhost\n" unless $vhost;
                die "Can't configure a plugin inside of a plugin\n" if $plugin;

                my $loaded = eval "use $class; 1;";
                die "Failed to load plugin $class: $@" if $@;
                $plugin = $class->new;
                $close_plugin->() if $immediate_close;
                return;
            }
            if ($line =~ m!</Plugin>!i) {
                $close_plugin->();
                return;
            }

            die "Syntax error: '$line'\n";
        };
        if ($@) {
            die "Configuration error on line $linenum: $@\n";
        }
    }
}

sub daemonize {
    my($pid, $sess_id, $i);

    ## Fork and exit parent
    if ($pid = fork) { exit 0; }

    ## Detach ourselves from the terminal
    Carp::croak("Cannot detach from controlling terminal")
        unless $sess_id = POSIX::setsid();

    ## Prevent possibility of acquiring a controling terminal
    $SIG{'HUP'} = 'IGNORE';
    if ($pid = fork) { exit 0; }

    ## Change working directory
    chdir "/";

    ## Clear file creation mask
    umask 0;

    ## Close open file descriptors
    close(STDIN);
    close(STDOUT);
    close(STDERR);

    ## Reopen stderr, stdout, stdin to /dev/null
    open(STDIN,  "+>/dev/null");
    open(STDOUT, "+>&STDIN");
    open(STDERR, "+>&STDIN");
}

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

1;

__END__

=head1 NAME

DJabberd - scalable, extensible Jabber/XMPP server.

=head1 SYNOPSIS

 $ djabberd --conf=config-file.conf --daemonize

=head1 DESCRIPTION

DJabberd was the answer to LiveJournal's Jabber (XMPP)
server needs.  We needed:

=over 4

=item * good performance for tons of connected users

=item * ability to scale to multiple nodes

=item * ability to hook into LiveJournal at all places, not just auth

=back

Basically we wanted the swiss army knife of Jabber servers (think
qpsmtpd or mod_perl), but none existed in any language.  While some
popular Jabber servers let us do pluggable auth, none let us get our
hands into roster storage, vcards, avatars, presence, etc.

So we made DJabberd.  It's a Jabber server where almost everything
defers to hooks to be implemented by plugins.  It does the core spec
itself (including SSL, StartTLS, server-to-server, etc), but it
doesn't come with any way to do authentication or storage or rosters,
etc.  You'll need to go pick up a plugin to do those.

You should be able to plop DJabberd into your existing systems /
userbase with minimal pain.  Just find a plugin that's close (if a
perfect match doesn't already exist!) and tweak.

DJabberd is event-based so we can have really low per-connection
memory requirements, smaller than is possible with a threaded jabber
server.  Because of this, all plugins can operate asynchronously,
taking as long as they want to finish their work, or to decline to the
next handler.  (in the meantime, while plugins wait on a response from
whatever they're talking to, the DJabberd event loop continues at full
speed) However, that's more work, so some plugins may choose to
operate synchronously, but they do so with the understanding that
those plugins will cause the whole server to get bogged down.  If
you're running a Jabber server for 5 users, you may not care that the
SQLite authentication backend pauses your server for milliseconds at a
time, but on a site with hundreds of thousands of connections, that
wouldn't be acceptable.  Watch out for those plugins.

=head1 HACKING

Read HookDocs.pm, read the major base classes (Authen, RosterStorage,
PresenceChecker), join the mailing list, ask questions ... we're here
to help.  If you want more hooks, let us know!  If we forgot one, it
doesn't hurt us to add more.

=head1 COPYRIGHT

This module is Copyright (c) 2006 Six Apart, Ltd.
All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=head1 WARRANTY

This is free software. IT COMES WITHOUT WARRANTY OF ANY KIND.

=head1 WEBSITE

Visit:

   http://danga.com/djabberd/

=head1 AUTHORS

Brad Fitzpatrick <brad@danga.com>

Artur Bergman <sky@crucially.net>

Jonathan Steinert <jsteinert@sixapart.com>

