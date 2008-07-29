package DJabberd::Connection;
use strict;
use warnings;
use base 'Danga::Socket';
use bytes;
use fields (
            'saxhandler',
            'parser',

            'bound_jid',      # undef until resource binding - then DJabberd::JID object

            'vhost',          # DJabberd::VHost instance (undef until they send a stream start element)
            'server',         # our DJabberd server object, which we used to find the VHost
            'ssl',            # undef when not in ssl mode, else the $ssl object from Net::SSLeay
            'stream_id',      # undef until set first time
            'to_host',        # undef until stream start
            'version',        # the DJabberd::StreamVersion we negotiated
            'rcvd_features',  # the features stanza we've received from the other party
            'log',            # Log::Log4perl object for this connection
            'xmllog',         # Log::Log4perl object that controls raw xml logging
            'id',             # connection id, used for logging purposes
            'write_when_readable',  # arrayref/bool, for SSL:  as boolean, we're only readable so we can write again.
                                    # but bool true is actually an arrayref of previous watch_read state
            'iqctr',          # iq counter.  incremented whenever we SEND an iq to the party (roster pushes, etc)
            'in_stream',      # bool:  true if we're in a stream tag
            'counted_close',  # bool:  temporary here to track down the overcounting of disconnects
            'disconnect_handlers',  # array of coderefs to call when this connection is closed for any reason

            'ssl_empty_read_ct', # int: number of consecutive empty SSL reads.
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

BEGIN {
    my $xmldebug = $ENV{XMLDEBUG};

    if ($xmldebug) {
        eval 'use constant XMLDEBUG => "' . quotemeta($xmldebug) . '"';
        die "XMLDEBUG path '$xmldebug' needs to be a directory writable by the user you are running $0 as\n" unless -w $xmldebug;
    } else {
        eval "use constant XMLDEBUG => ''";
    }
}

our %LOGMAP;

sub new {
    my ($class, $sock, $server) = @_;
    my $self = $class->SUPER::new($sock);

    croak("Server param not a DJabberd (server) object, '" . ref($server) . "'")
        unless $server->isa("DJabberd");

    $self->{vhost}   = undef;  # set once we get a stream start header from them.
    $self->{server}  = $server;
    Scalar::Util::weaken($self->{server});

    $self->{log}     = DJabberd::Log->get_logger($class);

    # hack to inject XML after Connection:: in the logger category
    my $xml_category = $class;
    $xml_category =~ s/Connection::/Connection::XML::/;

    $self->{xmllog}  = DJabberd::Log->get_logger($xml_category);

    my $fromip = $self->peer_ip_string || "<undef>";

    # a health check monitor doesn't get an id assigned/wasted on it, and doesn't log
    # so it's less annoying to look at:
    unless ($server->is_monitor_host($fromip)) {
        $self->{id}      = $connection_id++;
        $self->log->debug("New connection '$self->{id}' from $fromip");
    }

    if (XMLDEBUG) {
        system("mkdir -p " . XMLDEBUG ."/$$/");
        my $handle = IO::Handle->new;
        no warnings;
        my $from = $fromip || "outbound";
        my $filename = "+>" . XMLDEBUG . "/$$/$from-$self->{id}";
        open ($handle, $filename) || die "Cannot open $filename: $!";
        $handle->autoflush(1);
        $LOGMAP{$self} = $handle;
    }
    return $self;
}

sub log {
    return $_[0]->{log};
}

sub xmllog {
    return $_[0]->{xmllog};
}

sub handler {
    return $_[0]->{saxhandler};
}

sub vhost {
    my DJabberd::Connection $self = $_[0];
    return $self->{vhost};
}

sub server {
    my DJabberd::Connection $self = $_[0];
    return $self->{server};
}

sub bound_jid {
    my DJabberd::Connection $self = $_[0];
    return $self->{bound_jid};
}

sub new_iq_id {
    my DJabberd::Connection $self = shift;
    $self->{iqctr}++;
    return "iq$self->{iqctr}";
}

sub log_outgoing_data {
    my ($self, $text) = @_;
    my $id = $self->{id} ||= 'no_id';
    
    if($self->xmllog->is_debug) {
        $self->xmllog->debug("$id > " . $text);
    } else {
        local $DJabberd::ASXML_NO_TEXT = 1;
        $self->xmllog->info("$id > " . $text);
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

sub discard_parser {
    my DJabberd::Connection $self = shift;
    # TODOTEST: bunch of new connections speaking not-well-formed xml and getting booted, then watch for mem leaks
    my $p = $self->{parser}   or return;
    $self->{parser}        = undef;
    $self->{saxhandler}->cleanup;
    $self->{saxhandler} = undef;
    Danga::Socket->AddTimer(0, sub {
        $p->finish_push;
    });
}

my %free_parsers;  # $ns -> [ [parser,handler]* ]
sub borrow_a_parser {
    my DJabberd::Connection $self = $_[0];

    # get a parser off the freelist
    if ($self->{in_stream}) {
        my $ns = $self->namespace;
        my $freelist = $free_parsers{$ns} || [];
        if (my $ent = pop @$freelist) {
            ($self->{parser}, $self->{saxhandler}) = @$ent;
            $self->{saxhandler}->set_connection($self);
            # die "ASSERT" unless $self->{parser}{LibParser};
            return $self->{parser};
        }
    }

    # no parser?  gotta make one.
    my $handler = DJabberd::SAXHandler->new;
    my $p       = DJabberd::XMLParser->new(Handler => $handler);

    if ($self->{in_stream}) {
        # gotta get it into stream-able state with an open root node
        # so client can send us multiple stanzas.  unless we're waiting for
        # the start stream, in which case it may also have an xml declaration
        # like <?xml ... ?> at top, which can only come at top, so we need
        # a virgin parser.
        my $ns = $self->namespace;

        # this is kinda a hack, in that it hard-codes the namespace
        # prefixes 'db' and 'stream',...  however, RFC 3920 seection
        # 11.2.1, 11.2.3, etc say it's okay for historical reasons to
        # force the prefixes for both 'stream' and 'db'
        my $other = $ns eq "jabber:server" ? "xmlns:db='jabber:server:dialback'" : "";
        $p->parse_chunk_scalarref(\ qq{<stream:stream
                                           xmlns='$ns'
                                           xmlns:stream='http://etherx.jabber.org/streams'
                                           $other>});
    }

    $handler->set_connection($self);
    $self->{saxhandler} = $handler;
    $self->{parser} = $p;
    return $p;
}

sub return_parser {
    my DJabberd::Connection $self = $_[0];
    return unless $self->{server}->share_parsers;
    return unless $self->{in_stream};

    my $freelist = $free_parsers{$self->namespace} ||= [];

    # BIG FAT WARNING:  with fields objects, you can't do:
    #   my $p = delete $self->{parser}.
    # You'd think you could, but it leaves $self->{parser} with some magic fucked up undef/but not
    # value and $p's refcount never goes down.  Some Perl bug due to fields, weakrefs, etc?  Who knows.
    # This affects Perl 5.8.4, but not Perl 5.8.8.
    my $p       = $self->{parser};     $self->{parser} = undef;
    my $handler = $self->{saxhandler}; $self->{saxhandler} = undef;
    $handler->set_connection(undef);

    if (@$freelist < 5) {
        push @$freelist, [$p, $handler];

    } else {
        Danga::Socket->AddTimer(0, sub {
            $p->finish_push;
        });
    }
}

sub set_rcvd_features {
    my ($self, $feat_stanza) = @_;
    $self->{rcvd_features} = $feat_stanza;
}

sub set_bound_jid {
    my ($self, $jid) = @_;
    die unless $jid && $jid->isa('DJabberd::JID');
    $self->{bound_jid} = $jid;
}

sub set_to_host {
    my ($self, $host) = @_;
    $self->{to_host} = $host;
}

sub to_host {
    my $self = shift;
    return $self->{to_host} or
        die "To host accessed before it was set";
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

# this can fail to signal that this connection can't work on this
# vhost for instance, this vhost doesn't support s2s, so a serverin or
# dialback subclass can override this to return 0 when s2s isn't
# enabled for the vhost
sub set_vhost {
    my ($self, $vhost) = @_;
    Carp::croak("Not a DJabberd::VHost: $vhost") unless UNIVERSAL::isa($vhost, "DJabberd::VHost");
    $self->{vhost} = $vhost;
    Scalar::Util::weaken($self->{vhost});
    return 1;
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

sub process_incoming_stanza_from_s2s_out {
    my ($self, $node) = @_;

    my %stanzas = (
                   "{urn:ietf:params:xml:ns:xmpp-tls}starttls"  => 'DJabberd::Stanza::StartTLS',
                   "{http://etherx.jabber.org/streams}features" => 'DJabberd::Stanza::StreamFeatures',
                   );

    my $class = $stanzas{$node->element};
    unless ($class) {
        warn "Unknown/handled stanza: " . $node->element . " on connection ($self->{id}), " . ref($self) .  "\n";
        return;
    }

    my $obj = $class->downbless($node, $self);
    $obj->on_recv_from_server($self);
}

sub send_stanza {
    my ($self, $stanza) = @_;

    # getter subref for pre_stanza_write hooks to
    # get at their own private copy of the stanza
    my $cloned;
    my $getter = sub {
        return $cloned if $cloned;
        if ($self != $stanza->connection) {
            $cloned = $stanza->clone;
            $cloned->set_connection($self);
        } else {
            $cloned = $stanza;
        }
        return $cloned;
    };

    $self->vhost->hook_chain_fast("pre_stanza_write",
                                  [ $getter ],
                                  {
                                     # TODO: implement.
                                  },
                                  sub {
                                      # if any hooks called the $getter, instantiating
                                      # the $cloned copy, then that's what we write.
                                      # as an optimization (the fast path), we just
                                      # write the untouched, uncloned original.
                                      $self->write_stanza($cloned || $stanza);
                                  });
}

sub write_stanza {
    my ($self, $stanza) = @_;

    my $to_jid    = $stanza->to_jid  || die "missing 'to' attribute in ".$stanza->element_name." stanza";
    my $from_jid  = $stanza->from_jid;  # this can be iq
    my $elename   = $stanza->element_name;

    my $other_attrs = "";
    my $attrs = $stanza->attrs;
    while (my ($k, $v) = each %$attrs) {
        $k =~ s/.+\}//; # get rid of the namespace
        next if $k eq "to" || $k eq "from";
        $other_attrs .= "$k=\"" . exml($v) . "\" ";
    }

    my $from = "";
    die "no from" if ($elename ne 'iq' && !$from_jid);

    $from = $from_jid ? " from='" . $from_jid->as_string_exml . "'" : "";

    my $to_str = $to_jid->as_string_exml;
    my $ns = $self->namespace;

    my $xml = "<$elename $other_attrs to='$to_str'$from>" . $stanza->innards_as_xml . "</$elename>";

    if ($self->xmllog->is_info) {
        # refactor this out
        my $debug;
        if($self->xmllog->is_debug) {
            $debug = "<$elename $other_attrs to='$to_str'$from>" . $stanza->innards_as_xml . "</$elename>";
        } else {
            local $DJabberd::ASXML_NO_TEXT = 1;
            $debug = "<$elename $other_attrs to='$to_str'$from>" . $stanza->innards_as_xml . "</$elename>";
        }
        $self->log_outgoing_data($debug);
    }

    $self->write(\$xml);
}

sub namespace {
    my $self = shift;
    Carp::confess("namespace called on $self which has no namespace");
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

sub restart_stream {
    my DJabberd::Connection $self = shift;

    $self->{in_stream} = 0;

    # to be safe, we just discard the parser, as they might've sent,
    # say, "<starttls/><attack", knowing the next user will get that
    # parser with "<attack" open and get a parser error and be
    # disconnected.
    $self->discard_parser;
}


# this is a hack to get everything we print
# this is a slow down now, will fix later but
# eval is being annoying
sub write {
    my $self = shift;
    if (XMLDEBUG) {
        my $time = Time::HiRes::time;
        no warnings;
        my $data = $_[0];
        $data = $$data if (ref($data) eq 'SCALAR');
        $LOGMAP{$self}->print("$time\t> $data\n") if $LOGMAP{$self} &&  ref($data) ne 'CODE' ;
    }
    $self->SUPER::write(@_);
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
        unless ($data && length $data) {
            # a few of these in a row implies an EOF.  else it could
            # just be the underlying socket was readable, but there
            # wasn't enough of an SSL packet for OpenSSL/etc to return
            # any unencrypted data back to us.
            if (++$self->{'ssl_empty_read_ct'} >= 10) {
                $self->close('ssl_eof');
            }
            return;
        }
        $self->{'ssl_empty_read_ct'} = 0;
        $bref = \$data;
    } else {
        # non-ssl mode:
        $bref = $self->read(20_000);
    }

    return $self->close unless defined $bref;

    # clients send whitespace between stanzas as keep-alives.  let's just ignore those,
    # not going through the bother to checkout a parser and all.
    return if ! $self->{parser} && $$bref !~ /\S/;

    Carp::confess if ($self->{closed});

    if (XMLDEBUG) {
        my $time = Time::HiRes::time;
        $LOGMAP{$self}->print("$time\t< $$bref\n");
    }

    my $p = $self->{parser} || $self->borrow_a_parser;
    my $len = length $$bref;
    #$self->log->debug("$self->{id} parsing $len bytes...") unless $len == 1;

    # remove invalid low unicode code points which aren't allowed in XML,
    # but both iChat and gaim have been observed to send in the wild, often
    # when copy/pasting from bizarre sources.  this probably isn't compliant,
    # and there's a speed hit, so only regexp them out in quirks mode:
    if ($self->{vhost} && $self->{vhost}{quirksmode}) {
        $$bref =~ s/&\#([\da-f]{0,8});/DJabberd::Util::numeric_entity_clean($1)/ieg;
    }

    eval {
        $p->parse_chunk_scalarref($bref);
    };

    if ($@) {
        # FIXME: give them stream error before closing them,
        # wait until they get the stream error written to them before closing
        $self->discard_parser;
        $self->log->error("$self->{id} disconnected $self because: $@");
        $self->log->warn("$self->{id} parsing *****\n$$bref\n*******\n\n\n");
        $self->close;
        return;
    }

    # if we still have a handler and haven't already closed down (cleanly),
    # then let's consider giving our xml parser/sax pair back, if we're at
    # a good breaking point.
    if ((my $handler = $self->handler) && ! $self->{closed}) {
        my $depth = $handler->depth;
        if ($depth == 0 && $$bref =~ m!>\s*$!) {
            # if no errors and not inside a stanza, return our parser to save memory
            $self->return_parser;
        }
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
    my $xmlns      = delete $opts{'xmlns'} || "jabber:server";
    die if %opts;

    # {=init-version-is-max} -- we must announce the highest version we support
    my $our_version = $self->server->spec_version;
    my $ver_attr    = $our_version->as_attr_string;

    # by default we send the optional to='' attribute in our stream, but we have support for
    # disabling it for our test suite.
    $to = "to='$to'";
    $to = "" if $DJabberd::_T_NO_TO_IN_DIALBACKVERIFY_STREAM;

    # {=xml-lang}
    my $xml = qq{<?xml version="1.0" encoding="UTF-8"?><stream:stream $to xmlns:stream='http://etherx.jabber.org/streams' xmlns='}.exml($xmlns).qq{' xml:lang='en' $extra_attr $ver_attr>};
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
    $self->set_to_host($to_host) if $to_host;

    # Spec rfc3920 (dialback section) says: Note: The 'to' and 'from'
    # attributes are OPTIONAL on the root stream element.  (during
    # dialback)
    if ($to_host || ! $ss->announced_dialback) {
        my $exist_vhost = $self->vhost;
        my $vhost       = $self->server->lookup_vhost($to_host);

        return $self->close_no_vhost($to_host)
            unless ($vhost);

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

    my $extra_attr    = delete $opts{'extra_attr'} || "";
    my $features_body = delete $opts{'features'} || "";
    die if %opts;

    my $features = "";
    if ($ss->version->supports_features) {
        # unless we're already in SSL mode, advertise it as a feature...
        # {=must-send-features-on-1.0}
        if (!$self->{ssl}
            && $self->server->ssl_cert_file
            && !$self->isa("DJabberd::Connection::ServerIn")) {
            $features_body .= "<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls' />";
        }
        $features = qq{<stream:features>$features_body</stream:features>};
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
    unless ($self->{in_stream}) {
        $self->write(qq{<?xml version='1.0'?><stream:stream xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' id='bye' xml:lang='en'>});
    }

    $self->write("<stream:error><$err xmlns='urn:ietf:params:xml:ns:xmpp-streams'/>$infoxml</stream:error>");
    # {=error-must-close-stream}
    $self->close_stream;
}

sub close_no_vhost {
    my ($self, $vhost) = @_;

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

    # FIXME: send proper "vhost not found message"
    # spec says:
    #   -- we have to start stream back to them,
    #   -- then send stream error
    #   -- stream should have proper 'from' address (but what if we have 2+)
    # If the error occurs while the stream is being set up, the receiving entity MUST still send the opening <stream> tag, include the <error/> element as a child of the stream element, send the closing </stream> tag, and terminate the underlying TCP connection. In this case, if the initiating entity provides an unknown host in the 'to' attribute (or provides no 'to' attribute at all), the server SHOULD provide the server's authoritative hostname in the 'from' attribute of the stream header sent before termination

    $self->log->info("No vhost found for host '$vhost', disconnecting");
    $self->close;
    return;
}

sub close_stream {
    my ($self, $err) = @_;
    $self->write("</stream:stream>");
    $self->write(sub { $self->close; });
}

sub add_disconnect_handler {
    my ($self, $callback) = @_;
    $self->{disconnect_handlers} ||= [];
    push @{$self->{disconnect_handlers}}, $callback;
}

sub _run_callback_list {
    my ($self, $listref, @args) = @_;
    
    return unless ref $listref eq 'ARRAY';
    
    foreach my $callback (@$listref) {
        next unless ref $callback eq 'CODE';
        
        $callback->($self, @args);
    }
    
}

sub close {
    my DJabberd::Connection $self = shift;
    return if $self->{closed};


    if ($self->{counted_close}++) {
        $self->log->logcluck("We are about to increment the diconnect counter one time too many, but we didn't");
    } else {
        $DJabberd::Stats::counter{disconnect}++;
    }

    $self->log->debug("DISCONNECT: $self->{id}\n") if $self->{id};
    $self->_run_callback_list($self->{disconnect_handlers});

    if (my $ssl = $self->{ssl}) {
        $self->set_writer_func(sub { return 0 });
        Net::SSLeay::free($ssl);
        $self->{ssl} = undef;
    }

    if (my $p = $self->{parser}) {
        # libxml isn't reentrant apparently, so we can't finish_push
        # from inside an existint callback.  so schedule immediately,
        # after event loop.
        Danga::Socket->AddTimer(0, sub {
            $p->finish_push;
            $self->{saxhandler}->cleanup if $self->{saxhandler};
            $self->{saxhandler} = undef;
            $self->{parser}     = undef;
        });
    }
    if (XMLDEBUG) {
        $LOGMAP{$self}->close;
        delete $LOGMAP{$self};
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
