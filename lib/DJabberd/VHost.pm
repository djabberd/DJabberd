package DJabberd::VHost;
use strict;
use B ();       # improved debugging when hooks are called
use Carp qw(croak);
use DJabberd::Util qw(tsub as_bool);
use DJabberd::Log;
use DJabberd::Roster;
use Authen::SASL 'Perl';

our $logger = DJabberd::Log->get_logger();
our $hook_logger = DJabberd::Log->get_logger("DJabberd::Hook");

sub new {
    my ($class, %opts) = @_;

    my $self = {
        'server_name'     => lc(delete $opts{server_name} || ""),
        'require_ssl'     => delete $opts{require_ssl},
        # I heard that there is sasl authentication in s2s too. Might want
        # to revise the following accordingly
        'sasl_optional'   => delete $opts{sasl_optional},
        'sasl_mechanisms' => delete $opts{sasl_mechanisms},
        'sasl_security'   => delete $opts{sasl_security},
        's2s'             => delete $opts{s2s},
        'hooks'           => {},
        'server'          => undef,  # set when added to a server

        # local connections
        'jid2sock'        => {},  # bob@207.7.148.210/rez -> DJabberd::Connection
        'bare2fulls'      => {},  # barejids -> { fulljid -> 1 }

        'quirksmode'      => 1,

        'server_secret'   => undef,  # server secret we use for dialback HMAC keys.  trumped
                                     # if a plugin implements a cluster-wide keyed shared secret

        features          => [],     # list of features

        subdomain         => {},  # subdomain => plugin mapping of subdomains we should accept

        inband_reg        => 0,   # bool: inband registration

        roster_cache      => {},  # $barejid_str -> DJabberd::Roster

        roster_wanters    => {},  # $barejid_str -> [ [$on_success, $on_fail]+ ]

        disco_kids        => {},  # $jid_str -> "Description" - children of this vhost for service discovery
        plugin_types      => {},  # ref($plugin instance) -> 1
    };

    croak("Missing/invalid vhost name") unless
        $self->{server_name} && $self->{server_name} =~ /^[-\w\.]+$/;

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
    my $qualified_subdomain = $subdomain . "." . $self->{server_name};
    $logger->logdie("VHost '$self->{server_name}' already has '$subdomain' registered by plugin '$self->{subdomain}->{$qualified_subdomain}'")
        if $self->{subdomain}->{$qualified_subdomain};

    $self->{subdomain}->{$qualified_subdomain} = $plugin;
}

sub handles_domain {
    my ($self, $domain) = @_;
    if ($self->{server_name} eq $domain) {
        return 1;
    } elsif (exists $self->{subdomain}->{$domain}) {
        return 1;
    } else {
        return 0;
    }
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
        unless ($self->has_plugin_of_type("DJabberd::Delivery::Local")) {
            $logger->logwarn("Adding implicit plugin DJabberd::Delivery::Local");
            $self->add_plugin(DJabberd::Delivery::Local->new);
        }
        if ($self->s2s && ! $self->has_plugin_of_type("DJabberd::Delivery::S2S")) {
            $logger->logwarn("Adding implicit plugin DJabberd::Delivery::S2S");
            $self->add_plugin(DJabberd::Delivery::S2S->new);
        }
    }

    unless ($self->has_plugin_of_type("DJabberd::Delivery::Local")) {
        $logger->logwarn("No DJabberd::Delivery::Local delivery plugin configured");
    }

    if ($self->s2s && ! $self->has_plugin_of_type("DJabberd::Delivery::S2S")) {
        $logger->logdie("s2s enabled, but no implicit or explicit DJabberd::Delivery::S2S plugin.");
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

sub set_config_inbandreg {
    my ($self, $val) = @_;
    $self->{inband_reg} = as_bool($val);
}

sub set_config_childservice {
    my ($self, $val) = @_;

    my ($strjid, $desc) = split(/\s+/, $val, 2);

    my $jid = DJabberd::JID->new($strjid);
    $logger->logdie("Invalid JID ".$strjid) unless $jid;

    $desc ||= $jid->node;

    $logger->info("Registered $strjid as VHost child service: $desc");

    $self->{disco_kids}{$jid} = $desc;
}

sub allow_inband_registration {
    my $self = shift;
    return $self->{inband_reg};
}

sub set_config_requiressl {
    my ($self, $val) = @_;
    $self->{require_ssl} = as_bool($val);
}

sub set_config_sasloptional {
    my ($self, $val) = @_;
    $self->{sasl_optional} = as_bool($val);
}

sub set_config_saslmechanisms {
    my ($self, $val) = @_;
    $val =~ s/^\s*\b(.+)\b\s*$/$1/;
    $self->{sasl_mechanisms} = $val;
    $self->{sasl} = undef;
}

sub set_config_saslsecurity {
    my ($self, $val) = @_;
    $val =~ s/^\s*\b(.+)\b\s*$/$1/;
    $self->{sasl_security} = $val;
    $self->{sasl} = undef;
}

sub sasl {
    my $self = shift;
    unless ($self->{sasl}) {
        if (my $mechanisms = $self->{sasl_mechanisms}) {
            $self->{sasl} = DJabberd::SASL->new($mechanisms);
        }
    }
    return $self->{sasl};
}

sub sasl {
    my $self = shift;
    my $mechanisms = $self->{sasl_mechanisms};
    if (!$self->{sasl} && $mechanisms) {
        $self->{sasl} = Authen::SASL->new(
            mechanism => $mechanisms,
            callback => {
                 checkpass => sub {
                    my $sasl  = shift;
                    my ($user, $pass, $realm) = @_;

                    my $success;
                    if ($self->are_hooks("CheckCleartext")) {
                        $self->run_hook_chain(phase => "CheckCleartext",
                              args  => [ username => $user, password => $pass ], # no connection XXX
                              methods => {
                                  accept => sub { $success = 1 },
                                  reject => sub { $success = 0 },
                              },
                        );
                    }
                    return $success;
                },
                getsecret => sub {
                    my $sasl  = shift;
                    my ($user, $authname) = @_;
                    my $pass;

                    if ($self->are_hooks("GetPassword")) {
                        $self->run_hook_chain(phase => "GetPassword",
                              args  => [ username => $user, ], # no connection XXX
                              methods => {
                                  set => sub {
                                      my (undef, $good_password) = @_;
                                      $pass = $good_password;
                                  },
                              },
                        );
                    }
                    return $pass;
                },
            },
        );
    }
    return $self->{sasl};
}

# true if vhost has s2s enabled
sub s2s {
    my $self = shift;
    return $self->{s2s};
}

sub child_services {
    return $_[0]->{disco_kids};
}

sub server {
    my $self = shift;
    return $self->{server};
}

sub set_server {
    my ($self, $server) = @_;
    $self->{server} = $server;
    Scalar::Util::weaken($self->{server});
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
                        _phase     => $phase,
                        decline    => $dummy_sub,
                        declined   => $dummy_sub,
                        stop_chain => $dummy_sub,
                        %$methods,
                    }),
                    @$args) if $fallback;
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

    # pre-declared here so they're captured by closures below
    my ($cb, $try_another, $depth);
    my $hook_count = scalar @hooks;
    
    my $stopper = sub {
        $try_another = undef;
    };
    $try_another = sub {
        my $hk = shift @hooks
            or return;
        
        # conditional debug statement -- computing this is costly, so only do this
        # when we are actually running in debug mode --kane
        if ($logger->is_debug) {   
            $depth++;
            
            # most hooks are anonymous sub refs, and it's hard to determine where they
            # came from. Sub::Identify gives you only the name (which is __ANON__) and
            # the filename. This gives us both the filename and line number it's defined
            # on, giving the user a very clear pointer to which subref will be invoked --kane
            # 
            # Since this is B pokery, protect us from doing anything wrong and exiting the 
            # server accidentally. 
            my $cv   = B::svref_2object($hk); 
            my $line = eval { 
                # $obj is either a B::LISTOP or a B::COP, keep walking up 
                # till we reach the B::COP, so we can get the line number; 
                my $obj     = $cv->ROOT->first; 
                $obj = $obj->first while $obj->can('first'); 
                $obj->line; 
            } || "Unknown ($@)"; 
            $logger->debug( 
                "For phase [@$phase] invoking hook $depth of $hook_count defined at: ". 
                $cv->FILE .':'. $line
            );
        }

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
        _phase     => $phase->[0],           # just for leak tracking, not needed
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
    $self->{plugin_types}{ref $plugin} = 1;
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

sub has_plugin_of_type {
    my ($self, $class) = @_;
    return $self->{plugin_types}{$class};
}

sub register_hook {
    my ($self, $phase, $subref) = @_;
    Carp::croak("Can't register hook on a non-VHost") unless UNIVERSAL::isa($self, "DJabberd::VHost");

    $logger->logcroak("Undocumented hook phase: '$phase'") unless
        $DJabberd::HookDocs::hook{$phase};

    push @{ $self->{hooks}{$phase} ||= [] }, $subref;
}

# lookup a local user by fulljid
sub find_jid {
    my ($self, $jid) = @_;
    return $self->find_jid($jid->as_string) if ref $jid;
    my $sock = $self->{jid2sock}{$jid} or return undef;
    return undef if $sock->{closed};
    return $sock;
}

sub register_jid {
    my ($self, $jid, $conn, $cb) = @_;
    # $cb can ->registered, ->error
    $logger->info("Registering '$jid' to connection '$conn->{id}'");

    my $barestr = $jid->as_bare_string;
    my $fullstr = $jid->as_string;

    ## Yann asking: XXX is this scenario 2?
    if (my $econn = $self->{jid2sock}{$fullstr}) {
        $econn->stream_error("conflict");
    }

    $self->{jid2sock}{$fullstr} = $conn;
    ($self->{bare2fulls}{$barestr} ||= {})->{$fullstr} = 1;  # TODO: this should be the connection, not a 1, saves work in unregister JID?

    $cb->registered;
}

sub unregister_jid {
    my ($self, $jid, $conn) = @_;

    my $barestr = $jid->as_bare_string;
    my $fullstr = $jid->as_string;

    my $deleted_fulljid;
    if (my $exist = $self->{jid2sock}{$fullstr}) {
        if ($exist == $conn) {
            delete $self->{jid2sock}{$fullstr};
            $deleted_fulljid = 1;
        }
    }

    if ($deleted_fulljid) {
        if ($self->{bare2fulls}{$barestr}) {
            delete $self->{bare2fulls}{$barestr}{$fullstr};
            unless (%{ $self->{bare2fulls}{$barestr} }) {
                delete $self->{bare2fulls}{$barestr};
            }
        }
    }

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

    # kill cache if roster checked;
    my $barestr = $jid->as_bare_string;
    delete $self->{roster_cache}{$barestr};

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
        my $iq = "<iq to='" . $c->bound_jid->as_string_exml . "' type='set' id='$id'>$xml</iq>";
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

sub get_roster {
    my ($self, $jid, %meth) = @_;
    my $good_cb = delete $meth{'on_success'};
    my $bad_cb  = delete $meth{'on_fail'};
    Carp::croak("unknown args") if %meth;

    my $barestr = $jid->as_bare_string;

    # see if it's cached.
    if (my $roster = $self->{roster_cache}{$barestr}) {
        if ($roster->inc_cache_gets >= 3) {
            delete $self->{roster_cache}{$barestr};
        }
        $good_cb->($roster);
        return;
    }

    # upon connect there are three immediate requests of a user's
    # roster, then pretty much never again, but those three can,
    # depending on the client's preference between sending initial
    # presence vs. roster get first, be 3 loads in parallel, or 1,
    # then 2 in parallel.  in any case, multiple async loads can be in
    # flight at once, so let's keep a list of roster-wanters and only
    # do one request, then send the answer to everybody.  the
    # $kick_off_load is to keep track of whether or not this is the
    # first request that actually has to start loading it, or we're a
    # 2nd/3rd caller.
    my $kick_off_load = 0;

    my $list = $self->{roster_wanters}{$barestr} ||= [];
    $kick_off_load = 1 unless @$list;
    push @$list, [$good_cb, $bad_cb];
    return unless $kick_off_load;

    $self->run_hook_chain(phase => "RosterGet",
                          args  => [ $jid ],
                          methods => {
                              set_roster => sub {
                                  my $roster = $_[1];
                                  $self->{roster_cache}{$barestr} = $roster;

                                  # upon connect there are three immediate requests of a user's
                                  # roster, then pretty much never again, so we keep it cached 5 seconds,
                                  # then discard it.
                                  Danga::Socket->AddTimer(5.0, sub {
                                      delete $self->{roster_cache}{$barestr};
                                  });

                                  # call all the on-success items, but deleting the current list
                                  # first, lest any of the callbacks load more roster items
                                  delete $self->{roster_wanters}{$barestr};
                                  my $done = 0;
                                  foreach my $li (@$list) {
                                      $li->[0]->($roster);
                                      $done = 1 if $roster->inc_cache_gets >= 3;
                                  }

                                  # if they've used it three times, they're done with
                                  # the initial roster, probes, and broadcast, so drop
                                  # it early, not waiting for 5 seconds.
                                  if ($done) {
                                      delete $self->{roster_cache}{$barestr};
                                  }
                              },
                          },
                          fallback => sub {
                              # call all the on-fail items, but deleting the current list
                              # first, lest any of the callbacks load more roster items
                              delete $self->{roster_wanters}{$barestr};
                              foreach my $li (@$list) {
                                  $li->[1]->() if $li->[1];
                              }
                          });
}

# $jidarg can be a $jid for now.  future:  arrayref of jid objs
# $cb is $cb->($map) where $map is hashref of fulljidstr -> $presence_stanza_obj
sub check_presence {
    my ($self, $jidarg, $cb) = @_;

    my %map;
    my $add_presence = sub {
        my ($jid, $stanza) = @_;
        $map{$jid->as_string} = $stanza;
    };

    # this hook chain is a little different, it's expected
    # to always fall through to the end.
    $self->run_hook_chain(phase => "PresenceCheck",
                           args  => [ $jidarg, $add_presence ],
                           fallback => sub {
                               $cb->(\%map);
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
