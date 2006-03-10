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
            'version',    # the DJabberd::StreamVersion we negotiated
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

sub set_version {
    my ($self, $verob) = @_;
    $self->{version} = $verob;
}

sub version {
    my $self = shift;
    return $self->{version} or
        die "Version accessed before it was set";
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

    # make phase into an arrayref;
    $phase = [ $phase ] unless ref $phase;

    my @hooks;
    foreach my $ph (@$phase) {
        push @hooks, @{ $self->{server}->{hooks}->{$ph} || [] };
    }
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

    $self->run_hook_chain(phase => [ $self->incoming_stanza_hook_phases ],
                          args  => [ $node ],
                          fallback => sub {
                              $self->process_stanza_builtin($node);
                          });
}

sub incoming_stanza_hook_phases {
    return ("incoming_stanza");
}

sub process_stanza_builtin {
    my ($self, $node) = @_;

    my %stanzas = (
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

sub on_stream_start {
    my DJabberd::Connection $self = shift;
    my $ss = shift;

    die "on_stream_start not defined for $self";
}

sub start_init_stream {
    my DJabberd::Connection  $self = shift;
    my %opts = @_;
    my $extra_attr = delete $opts{'extra_attr'} || "";
    die if %opts;

    # {=init-version-is-max} -- we must announce the highest version we support
    my $our_version = $self->server->spec_version;
    my $ver_attr    = $our_version->as_attr_string;

    # {=xml-lang}
    $self->write(qq{<?xml version="1.0" encoding="UTF-8"?><stream:stream xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:server' xml:lang='en' $extra_attr $ver_attr>});
}

sub start_stream_back {
    my DJabberd::Connection  $self = shift;
    my DJabberd::StreamStart $ss   = shift;
    my %opts = @_;
    my $ns         = delete $opts{'namespace'} or
        die "No default namespace"; # {=stream-def-namespace}

    my $extra_attr = delete $opts{'extra_attr'} || "";
    die if %opts;

    my $features = "";
    if ($ss->version->supports_features) {
        # unless we're already in SSL mode, advertise it as a feature...
        # {=must-send-features-on-1.0}
        my $tls = "";
        unless ($self->{ssl}) {
            $tls = "<starttls xmsns='urn:ietf:params:xml:ns:xmpp-tls' />";
        }
        $features = qq{<stream:features>$tls</stream:features>};
    }

    # The receiving entity MUST set the value of the 'version'
    # attribute on the response stream header to either the value
    # supplied by the initiating entity or the highest version number
    # supported by the receiving entity, whichever is lower.
    # {=response-version-is-min}
    my $our_version = $self->server->spec_version;
    my $min_version = $ss->version->min($our_version);
    $self->set_version($min_version);
    my $ver_attr    = $min_version->as_attr_string;

    my $id = $self->stream_id;
    my $sname = $self->server->name;
    # {=streams-namespace}
    my $back = qq{<?xml version="1.0" encoding="UTF-8"?><stream:stream from="$sname" id="$id" $ver_attr $extra_attr xmlns:stream="http://etherx.jabber.org/streams" xmlns="$ns">$features};
    warn "Sending stream back: $back\n";
    $self->write($back);
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
    # {=stream-errors}
    $self->write("<stream:error><$err xmlns='xmlns='urn:ietf:params:xml:ns:xmpp-streams'/></stream:error>");
    # {=error-must-close-stream}
    $self->close_stream;
}

sub close_stream {
    my ($self, $err) = @_;
    $self->write("</stream:stream>");
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
