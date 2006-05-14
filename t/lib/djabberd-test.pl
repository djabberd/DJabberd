BEGIN {
    $ENV{LOGLEVEL} ||= "WARN";
}
use strict;
use DJabberd;
use DJabberd::Authen::AllowedUsers;
use DJabberd::Authen::StaticPassword;
use DJabberd::TestSAXHandler;
use DJabberd::RosterStorage::SQLite;
use DJabberd::RosterStorage::Dummy;
use DJabberd::RosterStorage::LiveJournal;

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

    two_parties_one_server($cb);
    sleep 1;
    two_parties_s2s($cb);
    sleep 1;
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

sub test_responses {
    my ($client, %map) = @_;
    my $n = values %map;
    # TODO: timeout on recv_xml_obj and die if don't get 'em all
    my @stanzas = map { $client->recv_xml_obj } (1..$n);

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

sub serverport {
    my $self = shift;
    return $self->{serverport} || "1100$self->{id}";
}

sub clientport {
    my $self = shift;
    return $self->{clientport} || "1000$self->{id}";
}

sub id {
    my $self = shift;
    return $self->{id};
}

sub hostname {
    my $self = shift;
    return "s$self->{id}.example.com";
}

sub link_with {
    my ($self, $other) = @_;
    push @{$self->{peers}}, $other;
}

sub start {
    my $self = shift;

    use FindBin qw($Bin);
    my $roster = "$Bin/t-roster-$self->{id}.sqlite";
    unlink $roster;

    my $vhost = DJabberd::VHost->new(
                                     server_name => $self->hostname,
                                     s2s         => 1,
                                     plugins   => [
                                                   DJabberd::Authen::AllowedUsers->new(policy => "deny",
                                                                                       allowedusers => [qw(partya partyb)]),
                                                   DJabberd::Authen::StaticPassword->new(password => "password"),
                                                   DJabberd::RosterStorage::SQLite->new(database => $roster),
                                                   ],
                                     );

    my $server = DJabberd->new;

    foreach my $peer (@{$self->{peers} || []}){
        $server->set_fake_s2s_peer($peer->hostname => DJabberd::IPEndPoint->new("127.0.0.1", $peer->serverport));
    }

    $server->add_vhost($vhost);
    $server->set_config_serverport($self->serverport);
    $server->set_config_clientport($self->clientport);

    my $childpid = fork;
    if (!$childpid) {
        $server->run;
        exit 0;
    }

    $self->{pid} = $childpid;
    return $self;
}

sub kill {
    my $self = shift;
    CORE::kill(9, $self->{pid});
}

package Test::DJabberd::Client;
use strict;

use overload
    '""' => \&as_string;

sub as_string {
    my $self = shift;
    return $self->{name} . '@' . $self->{server}->hostname;
}

sub server {
    my $self = shift;
    return $self->{server};
}

sub new {
    my $class = shift;
    my $self = bless {@_}, $class;
    die unless $self->{name};

    $self->start_new_parser;
    return $self;
}

sub get_event {
    my $self = shift;
    while (! @{$self->{events}}) {
        my $byte;
        my $rv = sysread($self->{sock}, $byte, 1);
        $self->{parser}->parse_more($byte);
    }
    return shift @{$self->{events}};
}

sub recv_xml {
    my $self = shift;
    my $ev = $self->get_event;
    die unless UNIVERSAL::isa($ev, "DJabberd::XMLElement");
    return $ev->as_xml;
}

sub recv_xml_obj {
    my $self = shift;
    my $ev = $self->get_event;
    die unless UNIVERSAL::isa($ev, "DJabberd::XMLElement");
    return $ev;
}

sub get_stream_start {
    my $self = shift;
    my $ev = $self->get_event();
    die unless $ev && $ev->isa("DJabberd::StreamStart");
    return $ev;
}

sub start_new_parser {
    my $self = shift;
    $self->{events} = [];
    $self->{parser} = DJabberd::XMLParser->new( Handler => DJabberd::TestSAXHandler->new($self->{events}) );
}

sub send_xml {
    my $self = shift;
    my $xml  = shift;
    $self->{sock}->print($xml);
}

sub login {
    my $self = shift;
    my $sock;
    for (1..3) {
        $sock = IO::Socket::INET->new(PeerAddr => "127.0.0.1:" . $self->server->clientport, Timeout => 1);
        last if $sock;
        sleep 1;
    }
    $self->{sock} = $sock
        or die "Cannot connect to server " . $self->server->id;

    my $to = $self->server->hostname;

    print $sock "
   <stream:stream
       xmlns:stream='http://etherx.jabber.org/streams'
       xmlns='jabber:client' to='$to' version='1.0'>";

    my $ss = $self->get_stream_start();

    my $features = $self->recv_xml;
    die "no features" unless $features =~ /^<features\b/;

    my $username = $self->{name};

    print $sock "<iq type='get' to='$to' id='auth1'>
  <query xmlns='jabber:iq:auth'/>
</iq>";

    my $authreply = $self->recv_xml;
    die "didn't get reply" unless $authreply =~ /id=.auth1\b/;
    my $response = "";
    if ($authreply =~ /\bpassword\b/) {
        $response = "<password>password</password>";
    } elsif ($authreply =~ /\bdigest\b/) {
        use Digest::SHA1 qw(sha1_hex);
        my $dig = lc(sha1_hex($ss->id . "password"));
        $response = "<digest>$dig</digest>";
    } else {
        die "can't do password nor digest auth: [$authreply]";
    }

    print $sock "<iq type='set' id='auth2'>
  <query xmlns='jabber:iq:auth'>
    <username>$username</username>
    $response
    <resource>testsuite</resource>
  </query>
</iq>";

    my $authreply2 = $self->recv_xml;
    die "no reply" unless $authreply2 =~ /id=.auth2\b/;
    die "bad password" unless $authreply2 =~ /type=.result\b/;

}

1;
