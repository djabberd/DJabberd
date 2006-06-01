package DJabberd::VHost;
use strict;
use Carp qw(croak);
use DJabberd::Util qw(tsub as_bool);
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger();
our $hook_logger = DJabberd::Log->get_logger("DJabberd::Hook");

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

        'quirksmode'  => 1,

        'server_secret' => undef,  # server secret we use for dialback HMAC keys.  trumped
                                   # if a plugin implements a cluster-wide keyed shared secret

        features            => [],     # list of features

        subdomain     => {},  # subdomain => plugin mapping of subdomains we should accept
    };

    croak("Missing/invalid vhost name") unless
        $self->{server_name} && $self->{server_name} =~ /^[\w\.]+$/;

    my $plugins = delete $opts{plugins};
    croak("Unknown vhost parameters: " . join(", ", keys %opts)) if %opts;

    bless $self, $class;

    $logger->info("Addding plugins...");
    foreach my $pl (@{ $plugins || [] }) {
        $self->add_plugin($pl);
    }

    return $self;
}

sub register_subdomain {
    my ($self, $subdomain, $plugin) = @_;
    $logger->logdie("VHost '$self->{server_name}' already has '$subdomain' registered by plugin '$self->{subdomain}->{$subdomain}'")
        if $self->{subdomain}->{$subdomain};

    $self->{subdomain}->{$subdomain} = $plugin;
}

sub server_name {
    my $self = shift;
    return $self->{server_name};
}

sub add_feature {
    my ($self, $feature) = @_;
    push @{$self->{features}}, $feature;
}

sub features {
    my ($self) = @_;
    return @{$self->{features}};
}

sub setup_default_plugins {
    my $self = shift;
    unless ($self->are_hooks("deliver")) {
        $self->add_plugin(DJabberd::Delivery::Local->new);
        $self->add_plugin(DJabberd::Delivery::S2S->new);
    }
    unless ($self->are_hooks("PresenceCheck")) {
        $self->add_plugin(DJabberd::PresenceChecker::Local->new);
    }
}

sub quirksmode { $_[0]{quirksmode} };

sub set_config_quirksmode {
    my ($self, $val) = @_;
    $self->{quirksmode} = as_bool($val);
}

sub set_config_s2s {
    my ($self, $val) = @_;
    $self->{s2s} = as_bool($val);
}

sub set_config_requiressl {
    my ($self, $val) = @_;
    $self->{require_ssl} = as_bool($val);
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

    my ($phase, $methods, $args, $fallback, $hook_inv)
        = @opts{qw(phase methods args fallback hook_invocant)};

    if (0) {
        delete @opts{qw(phase methods args fallback hook_invocant)};
        die if %opts;
    }

    hook_chain_fast($self,
                    $phase,
                    $args     || [],
                    $methods  || {},
                    $fallback || sub {},
                    $hook_inv);
}

my $dummy_sub = sub {};

sub hook_chain_fast {
    my ($self, $phase, $args, $methods, $fallback, $hook_inv) = @_;

    # fast path, no phases, only fallback:
    if ($self && ! ref $phase && ! @{ $self->{hooks}->{$phase} || []}) {
        $fallback->($self,
                    DJabberd::Callback->new({
                        decline    => $dummy_sub,
                        declined   => $dummy_sub,
                        stop_chain => $dummy_sub,
                        %$methods,
                    }),
                    @$args);
        return;
    }

    # make phase into an arrayref;
    $phase = [ $phase ] unless ref $phase;

    my @hooks;
    foreach my $ph (@$phase) {
        $logger->logcroak("Undocumented hook phase: '$ph'") unless
            $DJabberd::HookDocs::hook{$ph};

        # self can be undef if the connection object invokes us.
        # because sometimes there is no vhost, as in the case of
        # old serverin dialback without a to address.
        if ($self) {
            push @hooks, @{ $self->{hooks}->{$ph} || [] };
        }
    }
    push @hooks, $fallback if $fallback;

    my ($cb, $try_another);  # pre-declared here so they're captured by closures below
    my $stopper = sub {
        $try_another = undef;
    };
    $try_another = sub {
        my $hk = shift @hooks
            or return;

        $cb->{_has_been_called} = 0;  # cheating version of: $cb->reset;
        $hk->($self || $hook_inv,
              $cb,
              @$args);

        # just in case the last person in the chain forgets
        # to call a callback, we destroy the circular reference ourselves.
        unless (@hooks) {
            $try_another = undef;
            $cb = undef;
        }
    };
    $cb = DJabberd::Callback->new({
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
                $cb = undef;
            }
        },
        %$methods,
    });

    $try_another->();
}

# return the version of the spec we implement
sub spec_version {
    my $self = shift;
    return $self->{_spec_version} ||= DJabberd::StreamVersion->new("1.0");
}

sub name {
    my $self = shift;
    return $self->{server_name};
}

# vhost method
sub add_plugin {
    my ($self, $plugin) = @_;
    $logger->info("Adding plugin: $plugin");
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

    $logger->logcroak("Undocumented hook phase: '$phase'") unless
        $DJabberd::HookDocs::hook{$phase};

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
    return lc($jid->as_string) eq $self->{server_name};
}

# returns true if given jid is controlled by this vhost
sub handles_jid {
    my ($self, $jid) = @_;
    return 0 unless $jid;
    return lc($jid->domain) eq $self->{server_name};
}

sub roster_push {
    my ($self, $jid, $ritem) = @_;
    croak("no ritem") unless $ritem;

    # XMPP-IM: howwever a server SHOULD NOT push or deliver roster items
    # in that state to the contact. (None + Pending In)
    return if $ritem->subscription->is_none_pending_in;

    # TODO: single-server roster push only.   need to use a hook
    # to go across the cluster

    my $xml = "<query xmlns='jabber:iq:roster'>";
    $xml .= $ritem->as_xml;
    $xml .= "</query>";

    my @conns = $self->find_conns_of_bare($jid);
    foreach my $c (@conns) {
        next unless $c->is_available && $c->requested_roster;
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
    if ($handle eq "i") {
        # internal
        $cb->($self->{server_secret});
    } else {
        # bogus handle.  currently only handle "i" is supported.
        $cb->(undef);
    }
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
