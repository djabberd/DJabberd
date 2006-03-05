package DJabberd::Connection;
use strict;
use base 'Danga::Socket';
use fields (
            'jabberhandler',
            'builder',
            'parser',
            'stream_id',
            'authed',     # bool, if authenticated
            'username',   # username of user, once authenticated
            'resource',   # resource of user, once authenticated
            'server_name', # servername to send to user in stream header
            'server',     # DJabberd server instance
            'ssl',        # undef when not in ssl mode, else the $ssl object from Net::SSLeay
            );

use XML::SAX ();
use XML::SAX::Expat::Incremental 0.04;
use DJabberd::SAXHandler;
use DJabberd::JID;
use DJabberd::IQ;
use DJabberd::Message;
use Data::Dumper;

use Digest::SHA1 qw(sha1_hex);
use Net::SSLeay;
Net::SSLeay::load_error_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();   # Important!
Net::SSLeay::randomize();

# TODO: move this to a plugin;
use LWP::Simple;

$Net::SSLeay::ssl_version = 10; # Insist on TLSv1

my %jid2sock;  # bob@207.7.148.210/rez -> DJabberd::Connection
               # bob@207.7.148.210     -> DJabberd::Connection

sub find_connection {
    my ($class, $jid) = @_;
    my $sock = $jid2sock{$jid} or return undef;
    return undef if $sock->{closed};
    return $sock;
}

sub register_client {
    my ($class, $jid, $sock) = @_;
    warn "REGISTERING $jid  ==> $sock\n";
    $jid2sock{$jid} = $sock;
}

sub new {
    my ($class, $sock, $server) = @_;
    my $self = $class->SUPER::new($sock);

    warn "Server = $server\n";

    # FIXME: circular reference from self to jabberhandler to self, use weakrefs
    my $jabberhandler = $self->{'jabberhandler'} = DJabberd::SAXHandler->new($self);

    my $p = XML::SAX::Expat::Incremental->new( Handler => $jabberhandler );
    $self->{parser} = $p;
    $self->{server_name} = "207.7.148.210";

    $self->{server}   = $server;
    Scalar::Util::weaken($self->{server});

    warn "CONNECTION from " . $self->peer_ip_string . " == $self\n";

    return $self;
}

sub run_hook_chain {
    my $self = shift;
    my %opts = @_;

    my $phase    = delete $opts{'phase'};
    my $methods  = delete $opts{'methods'} || {};
    my $args     = delete $opts{'args'};
    my $fallback = delete $opts{'fallback'};
    die if %opts;

    my @hooks = @{ $self->{server}->{hooks}->{$phase} || [] };
    push @hooks, $fallback if $fallback;

    my $try_another;
    my $stopper = sub {
        $try_another = undef;
    };
    $try_another = sub {

        my $hk = shift @hooks
            or return;

        # TODO: look into circular references on closures
        $hk->($self,
              DJabberd::Callback->new(
                                      decline    => $try_another,
                                      stop_chain => $stopper,
                                      %$methods,
                                      ),
              @$args);

    };

    $try_another->();
}

sub server {
    my $self = shift;
    return $self->{'server'};
}

# called by DJabberd::SAXHandler
sub process_stanza {
    my ($self, $node) = @_;
    $self->run_hook_chain(phase => "stanza",
                          args => [ $node ]);
}

# from the JabberHandler
sub process_iq {
    my ($self, $iq) = @_;

}

sub jid {
    my $self = shift;
    my $jid = $self->{username} . '@' . $self->{server_name};
    $jid .= "/$self->{resource}" if $self->{resource};
    return $jid;
}

sub send_message {
    my ($self, $from, $msg) = @_;

    my $from_jid = $from->jid;
    my $my_jid   = $self->jid;

    my $message_back = "<message type='chat' to='$my_jid' from='$from_jid'>" . $msg->innards_as_xml . "</message>";
    warn "Message from $from_jid to $my_jid: $message_back\n";
    $self->write($message_back);
}

# DJabberd::Connection
sub event_read {
    my DJabberd::Connection $self = shift;

    my $bref;
    if (my $ssl = $self->{ssl}) {
        my $data = Net::SSLeay::read($ssl);

        my $errs = Net::SSLeay::print_errs('SSL_read');
        die "SSL Read error: $errs\n" if $errs;

        # Net::SSLeays buffers internally, so if we didn't read anything, it's
        # in its buffer
        return unless length $data;
        $bref = \$data;
    } else {
        # non-ssl mode:
        $bref = $self->read(20_000);
    }

    return $self->close unless defined $bref;

    my $p = $self->{parser};
    print "$self parsing more... [$$bref]\n";
    eval {
        $p->parse_more($$bref);
    };
    if ($@) {
        # FIXME: give them stream error before closing them,
        # wait until they get the stream error written to them before closing
        print "disconnected $self because: $@\n";
        $self->close;
        return;
    }
    print "$self parsed\n";
}

sub start_stream {
    my DJabberd::Connection $self = shift;
    my $id = $self->{stream_id} = Digest::SHA1::sha1_hex(rand() . rand() . rand());

    # unless we're already in SSL mode, advertise it as a feature...
    my $tls = "";
    unless ($self->{ssl}) {
        $tls = "<starttls xmsns='urn:ietf:params:xml:ns:xmpp-tls' />";
    }

    my $rv = $self->write(qq{<?xml version="1.0" encoding="UTF-8"?>
                                 <stream:stream from="$self->{server_name}" id="$id" version="1.0" xmlns:stream="http://etherx.jabber.org/streams" xmlns="jabber:client">
                                 <stream:features>
$tls
 </stream:features>
                             });
    return;
}

sub end_stream {
    my DJabberd::Connection $self = shift;
    $self->write("</stream:stream>");
    $self->write(sub { $self->close; });
    # TODO: unregister client from %jid2sock
}

sub event_write {
    my $self = shift;
    $self->watch_write(0) if $self->write(undef);
}

sub close {
    my DJabberd::Connection $self = shift;
    print "DISCONNECT: $self\n";

    if (my $ssl = $self->{ssl}) {
        Net::SSLeay::free($ssl);
    }

    $self->SUPER::close;
}


# DJabberd::Connection
sub event_err { my $self = shift; $self->close; }
sub event_hup { my $self = shift; $self->close; }


# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

1;
