package DJabberd::Connection;
use strict;
use warnings;
use base 'Danga::Socket';
use fields (
            'jabberhandler',
            'builder',
            'parser',
            'authed',     # bool, if authenticated
            'username',   # username of user, once authenticated
            'resource',   # resource of user, once authenticated
            'bound_jid',  # undef until resource binding - then DJabberd::JID object
            'vhost',      # DJabberd vhost instance (FIXME: for now just a server)
            'ssl',        # undef when not in ssl mode, else the $ssl object from Net::SSLeay
            'stream_id',  # undef until set first time
            'version',    # the DJabberd::StreamVersion we negotiated
            'rcvd_features',  # the features stanza we've received from the other party
            );


use XML::SAX ();
use XML::SAX::Expat::Incremental 0.04;
use Digest::SHA1 qw(sha1_hex);

use DJabberd::SAXHandler;
use DJabberd::JID;
use DJabberd::IQ;
use DJabberd::Message;
use DJabberd::Util qw(exml tsub);

use Data::Dumper;
use Carp qw(croak);

sub new {
    my ($class, $sock, $vhost) = @_;
    my $self = $class->SUPER::new($sock);

    warn "Vhost = $vhost\n";

    $self->start_new_parser;
    $self->{vhost}   = $vhost;
    Scalar::Util::weaken($self->{vhost});

    warn "CONNECTION from " . ($self->peer_ip_string || "<undef>") . " == $self\n";

    return $self;
}

sub start_new_parser {
    my $self = shift;

    # FIXME: circular reference from self to jabberhandler to self, use weakrefs
    my $jabberhandler = $self->{'jabberhandler'} = DJabberd::SAXHandler->new($self);
    my $p = XML::SAX::Expat::Incremental->new( Handler => $jabberhandler );
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
        croak("Undocumented hook phase: '$ph'") unless
            $DJabberd::HookDocs::hook{$ph};
        push @hooks, @{ $self->{vhost}->{hooks}->{$ph} || [] };
    }
    push @hooks, $fallback if $fallback;

    my $try_another;
    my $stopper = tsub {
        $try_another = undef;
    };
    $try_another = tsub {

        my $hk = shift @hooks
            or return;

        # TODO: look into circular references on closures
        $hk->($self,
              DJabberd::Callback->new(
                                      decline    => $try_another,
                                      declined   => $try_another,
                                      stop_chain => $stopper,
                                      %$methods,
                                      ),
              @$args);

        # experiment in stopping the common case of leaks
        unless (@hooks) {
            warn "Destroying hooks for phase $phase->[0]\n";
            $try_another = undef;
        }

    };

    $try_another->();
}

sub vhost {
    # FIXME: for now, server <-> vhost, but later servers will have multiple
    # vhosts
    my $self = shift;
    return $self->server;
}
sub server {
    my $self = shift;
    return $self->{'vhost'};
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
    my $jid = $self->{username} . '@' . $self->server->name;
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

    $self->run_hook_chain(phase => "pre_stanza_write",
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
    my $from_jid  = $stanza->from || die "no from";
    my $elename   = $stanza->element_name;

    my $other_attrs = "";
    while (my ($k, $v) = each %{ $stanza->attrs }) {
        $k =~ s/.+\}//; # get rid of the namespace
        next if $k eq "to" || $k eq "from";
        $other_attrs .= "$k=\"" . exml($v) . "\" ";
    }

    my $ns = $self->namespace;

    my $xml = "<$elename $other_attrs to='$to_jid' from='$from_jid'>" . $stanza->innards_as_xml . "</$elename>";

    if (1) {
        local $DJabberd::ASXML_NO_TEXT = 1;
        my $debug = "<$elename $other_attrs to='$to_jid' from='$from_jid'>" . $stanza->innards_as_xml . "</$elename>";
        warn "sending to $self:  $debug\n";
    }

    $self->write(\$xml);
}

sub namespace {
    return "";
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
        return unless $data && length $data;
        $bref = \$data;
    } else {
        # non-ssl mode:
        $bref = $self->read(20_000);
    }

    return $self->close unless defined $bref;

    my $p = $self->{parser};
    my $len = length $$bref;

    warn "$self parsing $len bytes...\n" unless $len == 1;
   
    eval {
        $p->parse_more($$bref);
    };
    if ($@) {
        # FIXME: give them stream error before closing them,
        # wait until they get the stream error written to them before closing
        print "disconnected $self because: $@\n";
        print "parsing *****\n$$bref\n*******\n\n\n";
        $self->close;
        return;
    }
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
        if (!$self->{ssl} && DJabberd::Stanza::StartTLS->can_do_ssl) {
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
    my $sname = $self->server->name;
    # {=streams-namespace}
    my $back = qq{<?xml version="1.0" encoding="UTF-8"?><stream:stream from="$sname" id="$id" $ver_attr $extra_attr xmlns:stream="http://etherx.jabber.org/streams" xmlns="$ns">$features};
    #warn "Sending stream back: $back\n";
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
    $self->write("<stream:error><$err xmlns='urn:ietf:params:xml:ns:xmpp-streams'/></stream:error>");
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
    warn "DISCONNECT: $self\n";

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
