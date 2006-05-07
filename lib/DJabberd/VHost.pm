package DJabberd::VHost;
use strict;
use Carp qw(croak);
use DJabberd::Util qw(tsub);
use DJabberd::Log;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);

our $logger = DJabberd::Log->get_logger();
our $hook_logger = DJabberd::Log->get_logger("DJabberd::VHost");

sub new {
    my ($class, %opts) = @_;

    my $self = {
        'server_name' => lc(delete $opts{server_name} || ""),
        'require_ssl' => delete $opts{require_ssl},
        's2s'         => delete $opts{s2s},
        'hooks'       => {},
        'server'      => undef,  # set when added to a server

        # local connections
        'jid2sock'    => {},  # bob@207.7.148.210/rez -> DJabberd::Connection
                              # bob@207.7.148.210     -> DJabberd::Connection
        'bare2fulls'  => {},  # barejids -> { fulljid -> 1 }

        'server_secret' => undef,  # server secret we use for dialback HMAC keys.  trumped
                                   # if a plugin implements a cluster-wide keyed shared secret
    };

    my $plugins = delete $opts{plugins};
    die "unknown opts" if %opts; #FIXME: better

    bless $self, $class;

    $logger->info("Addding plugins...");
    foreach my $pl (@{ $plugins || [] }) {
        $logger->info("  ... adding plugin: $pl");
        $self->add_plugin($pl);
    }

    return $self;
}

# true if vhost has s2s enabled
sub s2s {
    my $self = shift;
    return $self->{s2s};
}

sub server {
    my $self = shift;
    return $self->{server};
}

sub set_server {
    my ($self, $server) = @_;
    $self->{server} = $server;
}

sub run_hook_chain {
    my $self = shift;
    my %opts = @_;

    my $phase    = delete $opts{'phase'};
    my $methods  = delete $opts{'methods'} || {};
    my $args     = delete $opts{'args'}    || [];
    my $fallback = delete $opts{'fallback'};
    die if %opts;

    # make phase into an arrayref;
    $phase = [ $phase ] unless ref $phase;

    my @hooks;
    foreach my $ph (@$phase) {
        $logger->logcroak("Undocumented hook phase: '$ph'") unless
            $DJabberd::HookDocs::hook{$ph};
        push @hooks, @{ $self->{hooks}->{$ph} || [] };
    }
    push @hooks, $fallback if $fallback;

    my $try_another;
    my $stopper = tsub {
        $try_another = undef;
    };
    $try_another = tsub {

        my $hk = shift @hooks
            or return;

        $hk->($self,
              DJabberd::Callback->new(
                                      decline    => $try_another,
                                      declined   => $try_another,
                                      stop_chain => $stopper,
                                      _post_fire => sub {
                                          # when somebody fires this callback, we know
                                          # we're done (unless it was decline/declined)
                                          # and we need to clean up circular references
                                          my $fired = shift;
                                          unless ($fired =~ /^decline/) {
                                              $try_another = undef;
                                          }
                                      },
                                      %$methods,
                                      ),
              @$args);
    };

    $try_another->();
}

# return the version of the spec we implement
sub spec_version {
    my $self = shift;
    return $self->{_spec_version} ||= DJabberd::StreamVersion->new("1.0");
}

sub name {
    my $self = shift;
    return $self->{server_name} || die "No server name configured.";
    # FIXME: try to determine it
}

# vhost method
sub add_plugin {
    my ($self, $plugin) = @_;
    $plugin->register($self);
}

*requires_ssl = \&require_ssl;  # english
sub require_ssl {
    my $self = shift;
    return $self->{require_ssl};
}

sub are_hooks {
    my ($self, $phase) = @_;
    return scalar @{ $self->{hooks}{$phase} || [] } ? 1 : 0;
}

sub register_hook {
    my ($self, $phase, $subref) = @_;
    Carp::croak("Can't register hook on a non-VHost") unless UNIVERSAL::isa($self, "DJabberd::VHost");
    # TODO: die if bogus phase
    push @{ $self->{hooks}{$phase} ||= [] }, $subref;
}

sub find_jid {
    my ($self, $jid) = @_;
    if (ref $jid) {
        return $self->find_jid($jid->as_string) ||
               $self->find_jid($jid->as_bare_string);
    }
    my $sock = $self->{jid2sock}{$jid} or return undef;
    return undef if $sock->{closed};
    return $sock;
}

sub register_jid {
    my ($self, $jid, $sock) = @_;
    $logger->info("Registering '$jid' to connection '$sock->{id}'");

    my $barestr = $jid->as_bare_string;
    my $fullstr = $jid->as_string;
    $self->{jid2sock}{$fullstr} = $sock;
    $self->{jid2sock}{$barestr} = $sock;
    ($self->{bare2fulls}{$barestr} ||= {})->{$fullstr} = 1;
}

# given a bare jid, find all local connections
sub find_conns_of_bare {
    my ($self, $jid) = @_;
    my $barestr = $jid->as_bare_string;
    my @conns;
    foreach my $fullstr (keys %{ $self->{bare2fulls}{$barestr} || {} }) {
        my $conn = $self->find_jid($fullstr)
            or next;
        push @conns, $conn;
    }

    return @conns;
}

# returns true if given jid is recognized as "for the server"
sub uses_jid {
    my ($self, $jid) = @_;
    return 0 unless $jid;
    # FIXME: this does no canonicalization of server_name, for one
    return $jid->as_string eq $self->{server_name};
}

# returns true if given jid is controlled by this vhost
sub handles_jid {
    my ($self, $jid) = @_;
    return 0 unless $jid;
    # FIXME: this does no canonicalization of server_name, for one
    return $jid->domain eq $self->{server_name};
}

sub roster_push {
    my ($self, $jid, $ritem) = @_;
    croak("no ritem") unless $ritem;

    # FIXME: single-server roster push only.   need to use a hook
    # to go across the cluster

    my $xml = "<query xmlns='jabber:iq:roster'>";
    $xml .= $ritem->as_xml;
    $xml .= "</query>";

    my @conns = $self->find_conns_of_bare($jid);
    foreach my $c (@conns) {
        #TODO:  next unless $c->is_available;
        my $id = $c->new_iq_id;
        my $iq = "<iq to='" . $c->bound_jid->as_string . "' type='set' id='$id'>$xml</iq>";
        $c->xmllog->info($iq);
        $c->write(\$iq);
    }
}

sub get_secret_key {
    my ($self, $cb) = @_;
    $cb->("i", $self->{server_secret} ||= join('', map { rand() } (1..20)));
}

sub get_secret_key_by_handle {
    my ($self, $handle, $cb) = @_;
    $cb->($self->{server_secret}) if $handle eq "i";  # internal
    $cb->(undef);  # bogus handle
}

# FIXME: need to hmac not just stream_id, but (stream_id,origsever,recvserver)
#   actually, it's most important that the recvserver is included, otherwise
#   could act like us by connecting to recv server and issuing a result
#   that we'd previously given to our attackers.  origserver is useless to
#   include because it's a constant.
#
sub generate_dialback_result {
    my ($self, $stream_id, $cb) = @_;
    warn "generate_dialback_result($stream_id, $cb) ...\n";
    $self->get_secret_key(sub {
        my ($shandle, $secret) = @_;
        my $res = join("-", $shandle, hmac_sha1_hex($stream_id, $secret));
        warn "res = $res, from handle=$shandle, stream_id=$stream_id, secret=$secret\n";
        $cb->($res);
    });
}

sub verify_callback {
    my ($self, %args) = @_;
    my $stream_id  = delete $args{'stream_id'};
    my $restext    = delete $args{'result_text'};
    my $on_success = delete $args{'on_success'};
    my $on_failure = delete $args{'on_failure'};
    Carp::croak("args") if %args;

    my ($handle, $digest) = split(/-/, $restext);
    warn "verify callback, restext=[$restext], stream_id = $stream_id\n";

    $self->get_secret_key_by_handle($handle, sub {
        my $secret = shift;
        warn "secret by handle is = $secret\n";

        # bogus handle if no secret
        unless ($secret) {
            $on_failure->();
            return;
        }

        my $proper_digest = hmac_sha1_hex($stream_id, $secret);
        if ($digest eq $proper_digest) {
            warn "proper digest!\n";
            $on_success->();
        } else {
            warn "bad digest!\n";
            $on_failure->();
        }
    });
}

sub debug {
    my $self = shift;
    return unless $self->{debug};
    printf STDERR @_;
}


# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

1;
