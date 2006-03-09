package DJabberd::Connection;
use strict;
use base 'Danga::Socket';
use fields (
            'jabberhandler',
            'builder',
            'parser',
            'authed',     # bool, if authenticated
            'username',   # username of user, once authenticated
            'resource',   # resource of user, once authenticated
            'server',     # DJabberd server instance
            'ssl',        # undef when not in ssl mode, else the $ssl object from Net::SSLeay
            'stream_id',  # undef until set first time
            );

use XML::SAX ();
use XML::SAX::Expat::Incremental 0.04;
use Digest::SHA1 qw(sha1_hex);

use DJabberd::SAXHandler;
use DJabberd::JID;
use DJabberd::IQ;
use DJabberd::Message;

use Data::Dumper;

sub server {
    return $_[0]->{server};
}

sub new {
    my ($class, $sock, $server) = @_;
    my $self = $class->SUPER::new($sock);

    warn "Server = $server\n";

    # FIXME: circular reference from self to jabberhandler to self, use weakrefs
    my $jabberhandler = $self->{'jabberhandler'} = DJabberd::SAXHandler->new($self);

    my $p = XML::SAX::Expat::Incremental->new( Handler => $jabberhandler );
    $self->{parser} = $p;

    $self->{server}   = $server;
    Scalar::Util::weaken($self->{server});

    warn "CONNECTION from " . $self->peer_ip_string . " == $self\n";

    return $self;
}

sub stream_id {
    my $self = shift;
    return $self->{stream_id} ||= Digest::SHA1::sha1_hex(rand() . rand() . rand());
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
                          args => [ $node ],
                          fallback => sub {
                              $self->process_stanza_builtin($node);
                          });
}

sub process_stanza_builtin {
    my ($self, $node) = @_;

    my %stanzas = (
                   "{jabber:client}iq"      => 'DJabberd::IQ',
                   "{jabber:client}message" => 'DJabberd::Message',
                   "{urn:ietf:params:xml:ns:xmpp-tls}starttls" => 'DJabberd::Stanza::StartTLS',
                   );

    my $class = $stanzas{$node->element};
    unless ($class) {
        warn "Unknown/handled stanza: " . $node->element . "\n";
        return;
    }

    my $obj = $class->new($node);
    $obj->process($self);
}

sub jid {
    my $self = shift;
    my $jid = $self->{username} . '@' . $self->server->name;
    $jid .= "/$self->{resource}" if $self->{resource};
    return $jid;
}

sub send_message {
    my ($self, $from, $msg) = @_;

    my $from_jid = $from->jid;
    my $my_jid   = $self->jid;

    my $message_back = "<message type='chat' to='$my_jid' from='$from_jid'>" . $msg->innards_as_xml . "</message>";
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
    my $id = $self->stream_id;

    # unless we're already in SSL mode, advertise it as a feature...
    my $tls = "";
    unless ($self->{ssl}) {
        $tls = "<starttls xmsns='urn:ietf:params:xml:ns:xmpp-tls' />";
    }

    my $sname = $self->server->name;
    my $rv = $self->write(qq{<?xml version="1.0" encoding="UTF-8"?>
                                 <stream:stream from="$sname" id="$id" version="1.0" xmlns:stream="http://etherx.jabber.org/streams" xmlns="jabber:client">
                                 <stream:features>
$tls
</stream:features>});

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

sub stream_error {
    my ($self, $err) = @_;
    $self->write("<stream:error><$err xmlns='xmlns='urn:ietf:params:xml:ns:xmpp-streams'/></stream:error>");
    $self->write(sub { $self->close; });
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
