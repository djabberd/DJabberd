BEGIN {
    $ENV{LOGLEVEL} ||= "WARN";
}
use strict;
use DJabberd;
use DJabberd::Authen::AllowedUsers;
use DJabberd::Authen::StaticPassword;
use DJabberd::TestSAXHandler;
use DJabberd::RosterStorage::InMemoryOnly;
use DJabberd::RosterStorage::Dummy;
use DJabberd::RosterStorage::LiveJournal;
use DJabberd::Plugin::MUC;
use DJabberd::Util;
use IO::Socket::UNIX;

sub once_logged_in {
    my $cb = shift;
    my $server = Test::DJabberd::Server->new(id => 1);
    $server->start;
    my $pa = Test::DJabberd::Client->new(server => $server, name => "partya");
    $pa->login;
    $cb->($pa);
    $server->kill;
}

sub two_parties {
    my $cb = shift;

    if ($ENV{WILDFIRE_S2S}) {
        two_parties_wildfire_to_local($cb);
        return;
    }

    if ($ENV{WILDFIRE_TEST}) {
        two_parties_one_wildfire($cb);
        return;
    }

    two_parties_one_server($cb);
    sleep 1;
    two_parties_s2s($cb);
    sleep 1;
}

sub two_parties_one_wildfire {
    my $cb = shift;

    my $wf = Test::DJabberd::Server->new(id => 1,
                                         type => 'wildfire',
                                         clientport => 5222,
                                         serverport => 5269,
                                         hostname => 's2.example.com',
                                         connect_ip => '24.232.168.187',
                                         not_local => 1,
                                         );
    $wf->start;
    my $pa = Test::DJabberd::Client->new(server => $wf, name => "partya");
    my $pb = Test::DJabberd::Client->new(server => $wf, name => "partyb");

    $pa->create_fresh_account;
    $pb->create_fresh_account;

    $cb->($pa, $pb);

}

sub two_parties_wildfire_to_local {
    my $cb = shift;

    my $wf = Test::DJabberd::Server->new(id => 2,
                                         type => 'wildfire',
                                         clientport => 5222,
                                         serverport => 5269,
                                         hostname => 's2.example.com',
                                         connect_ip => '24.232.168.187',
                                         not_local => 1,
                                         );
    $wf->start;
    my $pa = Test::DJabberd::Client->new(server => $wf, name => "partya");
    $pa->create_fresh_account;

    my $server1 = Test::DJabberd::Server->new(id => 1);
    $server1->link_with($wf);
    my $pb = Test::DJabberd::Client->new(server => $server1, name => "partyb");

    $cb->($pa, $pb);
}

sub two_parties_one_server {
    my $cb = shift;

    my $server = Test::DJabberd::Server->new(id => 1);
    $server->start;

    my $pa = Test::DJabberd::Client->new(server => $server, name => "partya");
    my $pb = Test::DJabberd::Client->new(server => $server, name => "partyb");
    $cb->($pa, $pb);

    $server->kill;
}

sub two_parties_s2s {
    my $cb = shift;

    my $server1 = Test::DJabberd::Server->new(id => 1);
    my $server2 = Test::DJabberd::Server->new(id => 2);
    $server1->link_with($server2);
    $server2->link_with($server1);
    $server1->start;
    $server2->start;

    my $pa = Test::DJabberd::Client->new(server => $server1, name => "partya");
    my $pb = Test::DJabberd::Client->new(server => $server2, name => "partyb");
    $cb->($pa, $pb);

    $server1->kill;
    $server2->kill;
}

sub two_parties_cluster {
    my $cb = shift;

    my $server1 = Test::DJabberd::Server->new(id => 1);
    my $server2 = Test::DJabberd::Server->new(id => 2);
    # TODO: configure these to know about each other.
    $server1->start;
    $server2->start;

    my $pa = Test::DJabberd::Client->new(server => $server1, name => "partya");
    my $pb = Test::DJabberd::Client->new(server => $server2, name => "partyb");
    $cb->($pa, $pb);

    $server1->kill;
    $server2->kill;
}

sub test_responses {
    my ($client, %map) = @_;
    my $n = values %map;
    # TODO: timeout on recv_xml_obj and die if don't get 'em all
    my @stanzas;
    my $verbose = ($ENV{LOGLEVEL} || "") eq "DEBUG";
    for (1..$n) {
        warn "Reading stanza $_/$n...\n" if $verbose;
        push @stanzas, $client->recv_xml_obj;
        warn "Got stanza: " . $stanzas[-1]->as_xml . "\n" if $verbose;
    }

    my %unmatched = %map;
  STANZA:
    foreach my $s (@stanzas) {
        foreach my $k (keys %unmatched) {
            my $tester = $map{$k};
            my $okay = eval { $tester->($s, $s->as_xml); };
            if ($okay) {
                Test::More::pass("matched response '$k'");
                delete $unmatched{$k};
                next STANZA;
            }
        }
        Carp::croak("Didn't match stanza: " . $s->as_xml);
    }

}

package Test::DJabberd::Server;
use strict;
use overload
    '""' => \&as_string;

our $PLUGIN_CB;
our $VHOST_CB;
our @SUBDOMAINS;

sub as_string {
    my $self = shift;
    return $self->hostname;
}

sub new {
    my $class = shift;
    my $self = bless {@_}, $class;

    die unless $self->{id};
    return $self;
}

sub peeraddr {
    my $self = shift;
    return $self->{connect_ip} || ($self->{not_local} ? $self->{hostname} : "127.0.0.1");
}

sub serverport {
    my $self = shift;
    return $self->{serverport} || "1100$self->{id}";
}

sub clientport {
    my $self = shift;
    return $self->{clientport} || "1000$self->{id}";
}

sub adminport {
    my $self = shift;
    return $self->{adminport} || 0;
}

sub id {
    my $self = shift;
    return $self->{id};
}

sub hostname {
    my $self = shift;
    return $self->{hostname} || "s$self->{id}.example.com";
}

sub link_with {
    my ($self, $other) = @_;
    push @{$self->{peers}}, $other;
}

sub roster_name {
    my $self = shift;
    use FindBin qw($Bin);
    return "$Bin/t-roster-$self->{id}.sqlite";
}

sub roster {
    my $self = shift;
    my $roster = $self->roster_name;

    # We need to clear the cache so we can really unlink it, kind of ghetto
    my $dbh = DBI->connect("dbi:SQLite:dbname=$roster","","", { RaiseError => 1, PrintError => 0, AutoCommit => 1 });
    my $CachedKids_hashref = $dbh->{Driver}->{CachedKids};
    %$CachedKids_hashref = () if $CachedKids_hashref;
    unlink $roster;
    return $roster;
}

sub standard_plugins {
    my $self = shift;
    return [
            DJabberd::Authen::AllowedUsers->new(policy => "deny",
                                                allowedusers => [qw(partya partyb)]),
            DJabberd::Authen::StaticPassword->new(password => "password"),
            DJabberd::RosterStorage::InMemoryOnly->new(),
            ($ENV{T_MUC_ENABLE} ? (DJabberd::Plugin::MUC->new(subdomain => 'conference')) : ()),
            DJabberd::Delivery::Local->new,
            DJabberd::Delivery::S2S->new,
            ];
}

sub start {
    my $self = shift;
    my $type = $self->{type} || "djabberd";

    if ($type eq "djabberd") {
        my $plugins = shift || ($PLUGIN_CB ? $PLUGIN_CB->($self) : $self->standard_plugins);

        my $vhost = DJabberd::VHost->new(
                                         server_name => $self->hostname,
                                         s2s         => 1,
                                         plugins     => $plugins,
                                         );
        my $server = DJabberd->new;
        $server->set_config_unixdomainsocket($self->{unixdomainsocket}) if $self->{unixdomainsocket};

        foreach my $peer (@{$self->{peers} || []}){
            $server->set_fake_s2s_peer($peer->hostname => DJabberd::IPEndPoint->new($peer->peeraddr, $peer->serverport));
            foreach my $subdomain (@SUBDOMAINS) {
                $server->set_fake_s2s_peer($subdomain . '.' . $peer->hostname => DJabberd::IPEndPoint->new("127.0.0.1", $peer->serverport));
            }
        }

        $VHOST_CB->($vhost) if $VHOST_CB;

        $server->add_vhost($vhost);
        $server->set_config_serverport($self->serverport);
        $server->set_config_clientport($self->clientport);
        $server->set_config_adminport($self->adminport) if $self->adminport;

        my $childpid = fork;
        if (!$childpid) {
            $server->run;
            exit 0;
        }

        $self->{pid} = $childpid;
    }

    if ($type eq "wildfire") {
        #...
    }

    return $self;
}

sub kill {
    my $self = shift;
    if ($self->{pid}) {
        CORE::kill(9, $self->{pid});
        my $pid = delete $self->{pid};
        local $?; # we don't want to inherit the waited pid's exit status
        waitpid $pid, 0;
    }
}

sub DESTROY {
    my $self = shift;
    $self->kill;
}

package Test::DJabberd::Client;
use strict;

use overload
    '""' => \&as_string;

sub resource {
    return $_[0]{resource} ||= ($ENV{UNICODE_RESOURCE} ? "test\xe2\x80\x99s computer" : "testsuite_with_gibberish:'\"");
}

sub username {
    my $self = shift;
    return $self->{name};
}

sub password {
    my $self = shift;
    return $self->{password} || "password";
}

sub as_string {
    my $self = shift;
    return $self->username . '@' . $self->{server}->hostname;
}

sub server {
    my $self = shift;
    return $self->{server};
}

sub new {
    my $class = shift;
    my $self = bless {@_}, $class;
    $self->{events} = [];
    $self->{readbuf} = '';
    die unless $self->{name};
    return $self;
}

sub get_event {
    my ($self, $timeout, $midstream) = @_;
    $timeout ||= 10;

    my $handler = DJabberd::TestSAXHandler->new($self->{events});
    my $parser = DJabberd::XMLParser->new( Handler => $handler );
    if ($midstream) {
        $parser->parse_more("<stream:stream xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:client'>");
        pop @{$self->{events}};
    }

    my $undef = sub {
        my $why = shift;
        $parser->finish_push;
        #warn "Returning undef because: $why\n";
        return undef;
    };

    #$| = 1;
    #print "going to read...\n";

    my $get_byte;
    $get_byte = sub {
        if (length $self->{readbuf}) {
            my $byte = substr($self->{readbuf}, 0, 1, '');
            return $byte;
        }

        my $byte;
        my $rin = '';
        vec($rin, fileno($self->{sock}), 1) = 1;
        my $n = select($rin, undef, undef, $timeout)
            or return $undef->("select timeout");

        IO::Handle::blocking($self->{sock}, 0);
        my $rv = sysread($self->{sock}, $self->{readbuf}, 4096);
        IO::Handle::blocking($self->{sock}, 1);
        if (!$rv) {
            return $undef->("sysread no return");
        }
        $get_byte->();
    };

    while (! @{$self->{events}}) {
        my $byte = $get_byte->();
        return undef unless defined $byte;
        $parser->parse_more($byte);
    }
    my $ev = shift @{$self->{events}};
    #print "\ngot event: [$ev]\n";
    #if (UNIVERSAL::isa($ev, "DJabberd::XMLElement")) {
    #    print "  looks like: " . $ev->as_xml . "\n";
    #}

    $parser->finish_push;
    $handler->{on_end_capture} = undef;

    return $ev;
}

# if using $timeout, you're declaring that you can expect nothing and
# undef is returned.  otherwise must return XML.  (or die after 10 seconds)
sub recv_xml {
    my ($self, $timeout) = @_;
    my $ev = $self->get_event($timeout, 1);
    return undef if $timeout && !$ev;
    die unless UNIVERSAL::isa($ev, "DJabberd::XMLElement");
    return $ev->as_xml;
}

# if using $timeout, you're declaring that you can expect nothing and
# undef is returned.  otherwise must return XML.  (or die after 10 seconds)
sub recv_xml_obj {
    my ($self, $timeout) = @_;
    my $ev = $self->get_event($timeout, 1);
    die unless UNIVERSAL::isa($ev, "DJabberd::XMLElement");
    return $ev;
}

sub get_stream_start {
    my $self = shift;
    my $ev = $self->get_event();
    die unless $ev && $ev->isa("DJabberd::StreamStart");
    return $ev;
}

sub send_xml {
    my $self = shift;
    my $xml  = shift;
    $self->{sock}->print($xml);
}

sub create_fresh_account {
    my $self = shift;
    eval {
        warn "trying to login for " . $self->username . " ...\n" if $ENV{TESTDEBUG};
        if ($self->login) {
            warn "  Logged in.\n" if $ENV{TESTDEBUG};
            $self->send_xml(qq{<iq type='set' id='unreg1'>
                                   <query xmlns='jabber:iq:register'>
                                   <remove/>
                                   </query>
                                   </iq>});
            my $res = $self->recv_xml;
            die "Couldn't wipe our account: $res" unless $res =~ /type=.result./;
            warn "  unregistered.\n" if $ENV{TESTDEBUG};
        }
    };
    warn "Error logging in: [$@]" if $@ && $ENV{TESTDEBUG};

    warn "Connecting...\n" if $ENV{TESTDEBUG};
    $self->connect
        or die "Couldn't connect to server";

    warn "Connected, getting auth types..\n" if $ENV{TESTDEBUG};
    $self->send_xml(qq{<iq type='get' id='reg1'>
                             <query xmlns='jabber:iq:register'/>
                             </iq>});

    my $res = $self->recv_xml;
    die "No in-band reg instructions: $res" unless $res =~ qr/<instructions>/;

    my $user = $self->username;
    my $pass = $self->password;

    warn "registering ($user / $pass)...\n" if $ENV{TESTDEBUG};
    $self->send_xml(qq{<iq type='set' id='reg1'>
                             <query xmlns='jabber:iq:register'>
                             <username>$user</username>
                             <password>$pass</password>
                             </query>
                             </iq>});

    $res = $self->recv_xml;
    die "failed to reg account: $res" unless $res =~ qr/type=.result./;
    warn "created account.\n" if $ENV{TESTDEBUG};
    $self->disconnect;
    return 1;
}

sub disconnect {
    my $self = shift;
    $self->{sock} = undef;
}

sub connect {
    my $self = shift;

    my $sock;
    my $addr;
    if ($addr = $self->{unixdomainsocket}) {
        $sock = IO::Socket::UNIX->new(Peer => $addr);
    } else {
        $addr = join(':',
                     $self->server->peeraddr,
                     $self->server->clientport);
        for (1..3) {
            $sock = IO::Socket::INET->new(PeerAddr => $addr,
                                          Timeout => 1);
            last if $sock;
            sleep 1;
        }
    }

    $self->{sock} = $sock
        or die "Cannot connect to server " . $self->server->id . " ($addr)";

    my $to = $self->server->hostname;

    print $sock "
   <stream:stream
       xmlns:stream='http://etherx.jabber.org/streams'
       xmlns='jabber:client' to='$to' version='1.0'>";

    $self->{ss} = $self->get_stream_start();

    my $features = $self->recv_xml;
    die "no features" unless $features =~ /^<features\b/;
    return 1;
}

sub login {
    my $self = shift;
    my $password = shift || $self->password;

    warn "connecting for login..\n" if $ENV{TESTDEBUG};
    $self->connect or die "Failed to connect";

    warn ".. connected after login.\n" if $ENV{TESTDEBUG};

    my $ss = $self->{ss};
    my $sock = $self->{sock};
    my $to = $self->server->hostname;

    my $username = $self->{name};

    warn "getting auth types...\n" if $ENV{TESTDEBUG};
    print $sock "<iq type='get' id='auth1'>
  <query xmlns='jabber:iq:auth'/>
</iq>";

    my $authreply = $self->recv_xml;
    warn "auth reply for types: [$authreply]\n" if $ENV{TESTDEBUG};

    die "didn't get reply" unless $authreply =~ /id=.auth1\b/;
    my $response = "";
    if ($authreply =~ /\bpassword\b/) {
        $response = "<password>$password</password>";
    } elsif ($authreply =~ /\bdigest\b/) {
        use Digest::SHA1 qw(sha1_hex);
        my $dig = lc(sha1_hex($ss->id . $password));
        $response = "<digest>$dig</digest>";
    } else {
        die "can't do password nor digest auth: [$authreply]";
    }

    my $res = $self->resource;
    print $sock "<iq type='set' id='auth2'>
  <query xmlns='jabber:iq:auth'>
    <username>$username</username>
    $response
    <resource>$res</resource>
  </query>
</iq>";

    my $authreply2 = $self->recv_xml;
    warn "auth reply post-login: [$authreply2]\n" if $ENV{TESTDEBUG};

    die "no reply" unless $authreply2 =~ /id=.auth2\b/;
    die "bad password" unless $authreply2 =~ /type=.result\b/;

    $self->{ss} = undef;
    delete $self->{ss};

    return 1;
}

sub get_roster {
    my $self = shift;
    $self->{requested_roster}++;
    $self->send_xml(qq{<iq type='get' id='rosterplz'><query xmlns='jabber:iq:roster'/></iq>});
    my $xmlo = $self->recv_xml_obj;
    die unless $xmlo->as_xml =~ /type=.result.+jabber:iq:roster/s;
    return $xmlo;
}

sub initial_presence {
    my $self = shift;
    my $message = shift || 'Default Message';
    $self->send_xml(qq{<presence><status>$message</status></presence>});
    $self->{initial_presence}++;
}

# assumes no roster has been requested yet.
# assumes no initial presence has been sent yet.
sub subscribe_successfully {
    my ($self, $other) = @_;

    $self->send_xml(qq{<presence to='$other' type='subscribe' />});

    $other->recv_xml =~ /<pre.+\btype=.subscribe\b/
        or die "other party ($other) didn't get type='subscribe'\n";

    $other->send_xml(qq{<presence to='$self' type='subscribed' />});

    main::test_responses($self,
                         "presence" => sub {
                             my ($xo, $xml) = @_;
                             return 0 if $xml =~ /\btype=/;
                             return 0 unless $xml =~ /<presence\b/;
                             return 1;
                         },
                         "presence2" => sub {
                             my ($xo, $xml) = @_;
                             return 0 if $xml =~ /\btype=/;
                             return 0 unless $xml =~ /<presence\b/;
                             return 1;
                         },
                         "presence subscribed" => sub {
                             my ($xo, $xml) = @_;
                             return 0 unless $xml =~ /\btype=.subscribed\b/;
                             return 0 unless $xml =~ /\bfrom=.$other\b/;
                             return 1;
                         },
                         );
}

# this code is a bit duplicated from above, but it deals
# with initial presence and roster requested
# it also doesn't ack it

sub subscribe_to {
    my ($self, $to) = @_;
    my $from = $self;

    $from->send_xml(qq{<presence to='$to' type='subscribe' />});

    $from->{state}->{subscribe_to}->{$to}++;
    my @test;

    if ($from->{requested_roster}) {
        push @test, "roster push" => sub {
            my ($xo, $xml) = @_;
            my $subscription = $from->{state}->{subscribed_from}->{$to} ? "from" : "none";
            return 0 unless $xml =~ /jid=.$to./;
            return 0 unless $xml =~ /\bsubscription=.$subscription\b/;
            return 0 if !$from->{state}->{subscribed_from}->{$to} && $xml !~ /ask=.subscribe\b/;
            return 1;
        },
    }


    main::test_responses($from, @test) if(@test);
    my $xml = $to->recv_xml_obj;

    main::is($xml->attr("{}to"), $to->as_string, "to pb");
    main::is($xml->attr("{}from"), $from->as_string, "from a");
    main::is($xml->attr("{}type"), "subscribe", "type subscribe");
    $to->{state}->{subscribe_from}->{$from}++;



}

sub accept_subscription_from {
    my ($self, $from) = @_;

    $self->send_xml(qq{<presence to='$from' type='subscribed' />});
    $self->{state}->{subscribed_from}->{$from}++;

    my @test;
    if ($from->{requested_roster}) {
        push @test,"roster push" => sub {
                       my ($xo, $xml) = @_;
                       warn "B) $xml";
                       if ($from->{state}->{subscribed_from}->{$self}) {
                           $xml =~ /\bsubscription=.from\b/ && $xml =~ /ask=.subscribe\b/;
                       } else {
                           $xml =~ /\bsubscription=.to\b/;
                       }
                   };
        push @test,"roster push" => sub {
                       my ($xo, $xml) = @_;
                       if ($from->{state}->{subscribed_from}->{$self} && $self->{state}->{subscribed_from}->{$from}) {
                           $xml =~ /\bsubscription=.both\b/;
                       } else {
                           $xml =~ /\bsubscription=.to\b/;
                           1;
                       }
                   };

    }



    if ($from->{initial_presence} && $self->{initial_presence}) {
        push @test, "presence of user" => sub {
            my ($xo, $xml) = @_;
            $xml =~ /Default Message/;
        };
        push @test, "presence of user2" => sub {
            my ($xo, $xml) = @_;
            $xml =~ /Default Message/;
        };
    }

    if ($from->{initial_presence}) {
        push @test, "presence subscribed" => sub {
            my ($xo, $xml) = @_;
            return 0 unless $xml =~ /\btype=.subscribed\b/;
            return 0 unless $xml =~ /\bfrom=.$self\b/;
            return 1;
        };
    }
     main::test_responses($from, @test) if (@test);
    $from->{state}->{subscribed_to}->{$self}++;
    my $xml = $self->recv_xml;
    main::like($xml, qr/to=.$self\b/, "to $self");
    if ($from->{state}->{subscribed_from}->{$self} && $self->{state}->{subscribed_from}->{$from}) {
        main::like($xml, qr/subscription=.both\b/, "both");
    } else {
        main::like($xml, qr/subscription=.from\b/, "from");
    }
}
1;
