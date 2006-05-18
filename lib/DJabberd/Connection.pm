package DJabberd::Connection;
use strict;
use warnings;
use base 'Danga::Socket';
use fields (
            'jabberhandler',
            'builder',
            'parser',
            'authed',         # bool, if authenticated
            'username',       # username of user, once authenticated
            'resource',       # resource of user, once authenticated
            'bound_jid',      # undef until resource binding - then DJabberd::JID object
            'vhost',          # DJabberd::VHost instance (undef until they send a stream start element)
            'server',         # our DJabberd server object, which we used to find the VHost
            'ssl',            # undef when not in ssl mode, else the $ssl object from Net::SSLeay
            'stream_id',      # undef until set first time
            'version',        # the DJabberd::StreamVersion we negotiated
            'rcvd_features',  # the features stanza we've received from the other party
            'log',            # Log::Log4perl object for this connection
            'xmllog',         # Log::Log4perl object that controls raw xml logging
            'id',             # connection id, used for logging purposes
            'write_when_readable',  # arrayref/bool, for SSL:  as boolean, we're only readable so we can write again.
                                    # but bool true is actually an arrayref of previous watch_read state
            'iqctr',          # iq counter.  incremented whenever we SEND an iq to the party (roster pushes, etc)
            );

our $connection_id = 1;

use XML::SAX ();
use DJabberd::XMLParser;
use Digest::SHA1 qw(sha1_hex);

use DJabberd::SAXHandler;
use DJabberd::JID;
use DJabberd::IQ;
use DJabberd::Message;
use DJabberd::Util qw(exml tsub);

use Data::Dumper;
use Carp qw(croak);

use DJabberd::Log;
our $hook_logger = DJabberd::Log->get_logger("DJabberd::Hook");

use constant POLLIN        => 1;
use constant POLLOUT       => 4;

sub new {
    my ($class, $sock, $server) = @_;
    my $self = $class->SUPER::new($sock);

    croak("Server param not a DJabberd (server) object, actually a '$server'")
        unless ref $server eq "DJabberd";

    $self->start_new_parser;
    $self->{vhost}   = undef;  # set once we get a stream start header from them.
    $self->{server}  = $server;
    $self->{log}     = DJabberd::Log->get_logger($class);

    # hack to inject XML after Connection:: in the logger category
    my $xml_category = $class;
    $xml_category =~ s/Connection::/Connection::XML::/;
    $self->{xmllog}  = DJabberd::Log->get_logger($xml_category);

    $self->{id}      = $connection_id++;

    Scalar::Util::weaken($self->{vhost});
    $self->log->debug("New connection '$self->{id}' from " . ($self->peer_ip_string || "<undef>"));

    return $self;
}

sub log {
    return $_[0]->{log};
}

sub xmllog {
    return $_[0]->{xmllog};
}

sub new_iq_id {
    my $self = shift;
    $self->{iqctr}++;
    return "iq$self->{iqctr}";
}

sub log_outgoing_data {
    my ($self, $text) = @_;
    if($self->xmllog->is_debug) {
        $self->xmllog->debug("$self->{id} > " . $text);
    } else {
        local $DJabberd::ASXML_NO_TEXT = 1;
        $self->xmllog->info("$self->{id} > " . $text);
    }
}

sub log_incoming_data {
    my ($self, $node) = @_;
    if($self->xmllog->is_debug) {
        $self->xmllog->debug("$self->{id} < " . $node->as_xml);
    } else {
        local $DJabberd::ASXML_NO_TEXT = 1;
        $self->xmllog->info("$self->{id} < " . $node->as_xml);
    }
}

sub start_new_parser {
    my $self = shift;

    if (my $oldp = $self->{parser}) {
        # libxml reentrancy issue again.  see Connection close method comments.
        Danga::Socket->AddTimer(1, sub {
            $oldp->finish_push;
        });;
    }

    my $jabberhandler = $self->{'jabberhandler'} = DJabberd::SAXHandler->new($self);
    my $p = DJabberd::XMLParser->new( Handler => $jabberhandler );
    $self->{parser} = $p;
}

# TODO: maybe this should be moved down only into ServerOut connections?
sub set_rcvd_features {
    my ($self, $feat_stanza) = @_;
    $self->{rcvd_features} = $feat_stanza;
}

sub set_bound_jid {
    my ($self, $jid) = @_;
    die unless $jid && $jid->isa('DJabberd::JID');
    $self->{bound_jid} = $jid;
}

sub bound_jid {
    my ($self) = @_;
    return $self->{bound_jid};
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

# only use this run_hook_chain when
sub run_hook_chain {
    my $self = shift;
    my %opts = @_;
    $opts{hook_invocant} = $self;

    my $known_deprecated = delete $opts{deprecated};
    my ($pkg, $filename, $line) = caller;
    my $vhost = $self->vhost;

    unless ($known_deprecated) {
        warn("DEPRECATED caller ($pkg/$filename/$line) of run_hook_chain on a connection\n");
    }
    return DJabberd::VHost::run_hook_chain($vhost, %opts);
}

sub vhost {
    my $self = shift;
    return $self->{vhost};
}

# this can fail to signal that this connection can't work on this
# vhost for instance, this vhost doesn't support s2s, so a serverin or
# dialback subclass can override this to return 0 when s2s isn't
# enabled for the vhost
sub set_vhost {
    my ($self, $vhost) = @_;
    Carp::croak("Not a DJabberd::VHost: $vhost") unless UNIVERSAL::isa($vhost, "DJabberd::VHost");
    $self->{vhost} = $vhost;
    return 1;
}

sub server {
    my $self = shift;
    return $self->{server};
}

# called by DJabberd::SAXHandler
sub on_stanza_received {
    my ($self, $node) = @_;
    die "SUBCLASSES MUST OVERRIDE 'on_stanza_received' for $self\n";
}

# subclasses should override returning 0 or 1
sub is_server {
    die "Undefined 'is_server' for $_[0]";
}

sub process_stanza_builtin {
    my ($self, $node) = @_;

    my %stanzas = (
                   "{urn:ietf:params:xml:ns:xmpp-tls}starttls"  => 'DJabberd::Stanza::StartTLS',
                   "{http://etherx.jabber.org/streams}features" => 'DJabberd::Stanza::StreamFeatures',
                   );

    my $class = $stanzas{$node->element};
    unless ($class) {
        warn "Unknown/handled stanza: " . $node->element . "\n";
        return;
    }

    my $obj = $class->downbless($node, $self);
    $obj->process($self);
}

sub jid {
    my $self = shift;
    # FIXME: this should probably bound_jid (resource binding)
    my $jid = $self->{username} . '@' . $self->vhost->name;
    $jid .= "/$self->{resource}" if $self->{resource};
    return $jid;
}

sub send_stanza {
    my ($self, $stanza, @ex) = @_;
    die if @ex;

    # getter subref for pre_stanza_write hooks to
    # get at their own private copy of the stanza
    my $cloned;
    my $getter = tsub {
        return $cloned if $cloned;
        if ($self != $stanza->connection) {
            $cloned = $stanza->clone;
            $cloned->set_connection($self);
        } else {
            $cloned = $stanza;
        }
        return $cloned;
    };

    $self->vhost->run_hook_chain(phase => "pre_stanza_write",
                                 args  => [ $getter ],
                                 methods => {
                                     # TODO: implement.
                                 },
                                 fallback => tsub {
                                     # if any hooks called the $getter, instantiating
                                     # the $cloned copy, then that's what we write.
                                     # as an optimization (the fast path), we just
                                     # write the untouched, uncloned original.
                                     $self->write_stanza($cloned || $stanza);
                                 });
}

sub write_stanza {
    my ($self, $stanza, @ex) = @_;
    die "too many parameters" if @ex;

    my $to_jid    = $stanza->to   || die "no to";
    my $from_jid  = $stanza->from;  # this can be iq
    my $elename   = $stanza->element_name;

    my $other_attrs = "";
    while (my ($k, $v) = each %{ $stanza->attrs }) {
        $k =~ s/.+\}//; # get rid of the namespace
        next if $k eq "to" || $k eq "from";
        $other_attrs .= "$k=\"" . exml($v) . "\" ";
    }

    my $from = "";
    die "no from" if ($elename ne 'iq' && !$from_jid);

    $from = $from_jid ? qq{ from='$from_jid'} : "";

    my $ns = $self->namespace;

    my $xml = "<$elename $other_attrs to='$to_jid'$from>" . $stanza->innards_as_xml . "</$elename>";

    if ($self->xmllog->is_info) {
        # refactor this out
        my $debug;
        if($self->xmllog->is_debug) {
            $debug = "<$elename $other_attrs to='$to_jid'$from>" . $stanza->innards_as_xml . "</$elename>";
        } else {
            local $DJabberd::ASXML_NO_TEXT = 1;
            $debug = "<$elename $other_attrs to='$to_jid'$from>" . $stanza->innards_as_xml . "</$elename>";
        }
        $self->log_outgoing_data($debug);
    }

    $self->write(\$xml);
}

sub namespace {
    return "";
}

# return SSL state object.  more useful as a boolean if conn is in SSL mode.
sub ssl {
    my $self = shift;
    return $self->{ssl};
}

# called by Danga::Socket when a write doesn't fully go through.  by default it
# enables writability.  but we want to do nothing if we're waiting for a read for SSL
sub on_incomplete_write {
    my $self = shift;
    return if $self->{write_when_readable};
    $self->SUPER::on_incomplete_write;
}

# called by SSL machinery to let us know a write is stalled on readability.
# so we need to (at least temporarily) go readable and then process writes.
sub write_when_readable {
    my $self = shift;

    # enable readability, but remember old value so we can pop it back
    my $prev_readable = ($self->{event_watch} & POLLIN)  ? 1 : 0;
    $self->watch_read(1);
    $self->{write_when_readable} = [ $prev_readable ];

    # don't need to push/pop its state because Danga::Socket->write, called later,
    # will do the one final write, or if not all written, will turn on watch_write
    $self->watch_write(0);
}

# DJabberd::Connection
sub event_read {
    my DJabberd::Connection $self = shift;

    # for async SSL:  if a session renegotation is in progress,
    # our previous write wants us to become readable first.
    # we then go back into the write path (by flushing the write
    # buffer) and it then does a read on this socket.
    if (my $ar = $self->{write_when_readable}) {
        $self->{write_when_readable} = 0;
        $self->watch_read($ar->[0]);  # restore previous readability state
        $self->watch_write(1);
        return;
    }

    my $bref;
    if (my $ssl = $self->{ssl}) {
        my $data = Net::SSLeay::read($ssl);

        my $errs = Net::SSLeay::print_errs('SSL_read');
        if ($errs) {
            warn "SSL Read error: $errs\n";
            $self->close;
            return;
        }

        # Net::SSLeays buffers internally, so if we didn't read anything, it's
        # in its buffer
        return unless $data && length $data;
        $bref = \$data;
    } else {
        # non-ssl mode:
        $bref = $self->read(20_000);
    }

    return $self->close unless defined $bref;

    my $p = $self->{parser};
    my $len = length $$bref;

    $self->log->debug("$self->{id} parsing $len bytes...") unless $len == 1;

    eval {
        $p->parse_chunk_scalarref($bref);
    };
    if ($@) {
        # FIXME: give them stream error before closing them,
        # wait until they get the stream error written to them before closing
        $self->log->error("$self->{id} disconnected $self because: $@");
        $self->log->warn("$self->{id} parsing *****\n$$bref\n*******\n\n\n");
        $self->close;
        return;
    }
}

sub on_stream_start {
    my DJabberd::Connection $self = shift;
    my $ss = shift;

    die "on_stream_start not defined for $self";
}

# when we're the client of a stream (we're talking first)
sub start_init_stream {
    my DJabberd::Connection  $self = shift;
    my %opts = @_;
    my $extra_attr = delete $opts{'extra_attr'} || "";
    my $to         = delete $opts{'to'} || Carp::croak("need 'to' domain");
    die if %opts;

    # {=init-version-is-max} -- we must announce the highest version we support
    my $our_version = $self->server->spec_version;
    my $ver_attr    = $our_version->as_attr_string;

    # {=xml-lang}
    my $xml = qq{<?xml version="1.0" encoding="UTF-8"?><stream:stream to='$to' xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:server' xml:lang='en' $extra_attr $ver_attr>};
    $self->log_outgoing_data($xml);
    $self->write($xml);
}

# sending a stream when we're the server (replier) of the stream. a client already
# started one with us (the $ss object)
sub start_stream_back {
    my DJabberd::Connection  $self = shift;
    my DJabberd::StreamStart $ss   = shift;

    # bind us to a vhost now.
    my $to_host     = $ss->to;

    # Spec rfc3920 (dialback section) says: Note: The 'to' and 'from'
    # attributes are OPTIONAL on the root stream element.  (during
    # dialback)
    if ($to_host || ! $ss->announced_dialback) {
        my $exist_vhost = $self->vhost;
        my $vhost       = $self->server->lookup_vhost($to_host);

        unless ($vhost) {
            # FIXME: send proper "vhost not found message"
            # spec says:
            #   -- we have to start stream back to them,
            #   -- then send stream error
            #   -- stream should have proper 'from' address (but what if we have 2+)
            #
            # If the error occurs while the stream is being set up, the
            # receiving entity MUST still send the opening <stream> tag,
            # include the <error/> element as a child of the stream
            # element, send the closing </stream> tag, and terminate the
            # underlying TCP connection. In this case, if the initiating
            # entity provides an unknown host in the 'to' attribute (or
            # provides no 'to' attribute at all), the server SHOULD
            # provide the server's authoritative hostname in the 'from'
            # attribute of the stream header sent before termination
            $self->log->info("No vhost found for host '$to_host', disconnecting");
            $self->close;
            return;
        }

        # if they previously had a stream open, it shouldn't change (after SASL/SSL)
        if ($exist_vhost && $exist_vhost != $vhost) {
            $self->log->info("Vhost changed for connection, disconnecting.");
            $self->close;
            return;
        }

        # set_vhost returns 0 to signal that this connection won't
        # accept this vhost.  and by then it probably closed the stream
        # with an error, so we just stop processing if we can't set it.
        return unless $self->set_vhost($vhost);
    }

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
        if (!$self->{ssl}
            && DJabberd::Stanza::StartTLS->can_do_ssl
            && !$self->isa("DJabberd::Connection::ServerIn")) {
            $tls = "<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls' />";
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

    # only include a from='hostname' attribute if we know our vhost.
    # if they didn't send one to set us, it's probably dialback
    # and they can cope without knowing ours yet.
    my $vhost = $self->vhost;
    my $sname = $vhost ? $vhost->name : "";
    my $from_attr = $sname ? "from='$sname'" : "";

    # {=streams-namespace}
    my $back = qq{<?xml version="1.0" encoding="UTF-8"?><stream:stream $from_attr id="$id" $ver_attr $extra_attr xmlns:stream="http://etherx.jabber.org/streams" xmlns="$ns">$features};
    $self->log_outgoing_data($back);
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

# info is optional descriptive text
sub stream_error {
    my ($self, $err, $info) = @_;
    $info ||= "";

    # {=stream-errors}
    $self->log->warn("$self->{id} stream error '$err': $info");
    my $infoxml = "";
    if ($info) {
        $infoxml = "<text xmlns='urn:ietf:params:xml:ns:xmpp-streams'>" . exml($info) . "</text>";
    }
    $self->write("<stream:error><$err xmlns='urn:ietf:params:xml:ns:xmpp-streams'/>$infoxml</stream:error>");
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
    $self->log->debug("DISCONNECT: $self->{id}\n");

    if (my $ssl = $self->{ssl}) {
        Net::SSLeay::free($ssl);
    }

    my $p       = $self->{parser};
    my $handler = $self->{jabberhandler};

    # libxml isn't reentrant apparently, so we can't finish_push
    # from inside an existint callback.  so schedule for a bit later.
    # this probably could be 0 seconds later, but who cares.
    Danga::Socket->AddTimer(1, sub {
        $p->finish_push;
    });

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
