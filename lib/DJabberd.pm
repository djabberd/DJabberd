#!/usr/bin/perl

# TODO: ignore the "     " spaces in between end/start events?  used as keep-alive
#
# TODO: server to server... port 5269

use strict;
use Carp;
use Danga::Socket 1.49;
use IO::Socket::INET;
use POSIX ();
use XML::SAX ();
use XML::SAX::Expat::Incremental 0.04;
#use XML::XPath;
#use XML::XPath::Builder;
#use XML::Filter::Tee;
use IO::Socket::SSL;
use LWP::Simple;
use Digest::SHA1 qw(sha1_hex);
#use DJabberd::SSL;
use DJabberd::SAXHandler;
use DJabberd::JID;
use DJabberd::IQ;
use DJabberd::Message;
use DJabberd::Callback;
use Scalar::Util;
use Net::SSLeay;

Net::SSLeay::load_error_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();   # Important!
Net::SSLeay::randomize();

$Net::SSLeay::ssl_version = 10; # Insist on TLSv1

package DJabberd;
use strict;
use Socket qw(IPPROTO_TCP TCP_NODELAY SOL_SOCKET SOCK_STREAM);

sub new {
    my ($class, %opts) = @_;

    my $self = {
        'daemonize' => delete $opts{daemonize},
        'auth_hooks' => delete $opts{auth_hooks},
    };
    die "unknown opts" if %opts; #FIXME: better

    return bless $self, $class;
}

sub debug {
    my $self = shift;
    return unless $self->{debug};
    printf STDERR @_;
}

sub run {
    my $self = shift;
    daemonize() if $self->{daemonize};

    local $SIG{'PIPE'} = "IGNORE";  # handled manually

    # establish SERVER socket, bind and listen.
    my $server = IO::Socket::INET->new(LocalPort => 5222,  # {=clientportnumber}
                                       Type      => SOCK_STREAM,
                                       Proto     => IPPROTO_TCP,
                                       Blocking  => 0,
                                       Reuse     => 1,
                                       Listen    => 10 )
        or die "Error creating socket: $@\n";

    # Not sure if I'm crazy or not, but I can't see in strace where/how
    # Perl 5.6 sets blocking to 0 without this.  In Perl 5.8, IO::Socket::INET
    # obviously sets it from watching strace.
    IO::Handle::blocking($server, 0);

    my $accept_handler = sub {
        my $csock = $server->accept();
        return unless $csock;

        $self->debug("Listen child making a Client for %d.\n", fileno($csock));

        IO::Handle::blocking($csock, 0);
        setsockopt($csock, IPPROTO_TCP, TCP_NODELAY, pack("l", 1)) or die;

        my $client = Client->new($csock, $self);
        $client->watch_read(1);
    };

    Client->OtherFds(fileno($server) => $accept_handler);
    Client->EventLoop();
}

# <LJFUNC>
# name: LJ::exml
# class: text
# des: Escapes a value before it can be put in XML.
# args: string
# des-string: string to be escaped
# returns: string escaped.
# </LJFUNC>
sub exml
{
    # fast path for the commmon case:
    return $_[0] unless $_[0] =~ /[&\"\'<>\x00-\x08\x0B\x0C\x0E-\x1F]/;
    # what are those character ranges? XML 1.0 allows:
    # #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]

    my $a = shift;
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&apos;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    $a =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    return $a;
}

sub daemonize {
    my($pid, $sess_id, $i);

    ## Fork and exit parent
    if ($pid = fork) { exit 0; }

    ## Detach ourselves from the terminal
    Carp::croak("Cannot detach from controlling terminal")
        unless $sess_id = POSIX::setsid();

    ## Prevent possibility of acquiring a controling terminal
    $SIG{'HUP'} = 'IGNORE';
    if ($pid = fork) { exit 0; }

    ## Change working directory
    chdir "/";

    ## Clear file creation mask
    umask 0;

    ## Close open file descriptors
    close(STDIN);
    close(STDOUT);
    close(STDERR);

    ## Reopen stderr, stdout, stdin to /dev/null
    open(STDIN,  "+>/dev/null");
    open(STDOUT, "+>&STDIN");
    open(STDERR, "+>&STDIN");
}

#####################################################################
### C L I E N T   C L A S S
#####################################################################
package Client;

use Danga::Socket;
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

my %jid2sock;  # bob@207.7.148.210/rez -> Client
               # bob@207.7.148.210     -> Client

sub find_client {
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

use Data::Dumper;

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

sub server {
    my $self = shift;
    return $self->{'server'};
}

sub process_stanza {
    my ($self, $node) = @_;

    if ($node->element eq "{jabber:client}iq") {
        my $iq = DJabberd::IQ->new($node);
        return $self->process_iq($iq);
    }

    if ($node->element eq "{jabber:client}message") {
        my $iq = DJabberd::Message->new($node);
        return $self->process_message($iq);
    }

    if ($node->element eq "{urn:ietf:params:xml:ns:xmpp-tls}starttls") {
        return $self->process_starttls($node);;
    }

    warn "Unknown packet: " . Dumper($node);
    return;
}

use Symbol qw(gensym);

sub process_starttls {
    my ($self, $node) = @_;
    $self->write("<proceed xmlns='urn:ietf:params:xml:ns:xmpp-tls' />");

    my $ctx = Net::SSLeay::CTX_new()
        or die("Failed to create SSL_CTX $!");

    Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL)
        and Net::SSLeay::die_if_ssl_error("ssl ctx set options");

    Net::SSLeay::CTX_set_mode($ctx, 1)  # enable partial writes
        and Net::SSLeay::die_if_ssl_error("ssl ctx set options");

    # Following will ask password unless private key is not encrypted
    Net::SSLeay::CTX_use_RSAPrivateKey_file ($ctx, 'server-key.pem',
                                             &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("private key");

    Net::SSLeay::CTX_use_certificate_file ($ctx, 'server-cert.pem',
                                           &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("certificate");


    my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    $self->{ssl} = $ssl;

    Net::SSLeay::set_verify($ssl, Net::SSLeay::VERIFY_PEER(), 0);

    my $fileno = $self->{sock}->fileno;
    warn "setting ssl ($ssl) fileno to $fileno\n";
    Net::SSLeay::set_fd($ssl, $fileno);

    $Net::SSLeay::trace = 2;

    #Net::SSLeay::connect($ssl) or Net::SSLeay::die_now("Failed SSL connect ($!)");
    my $err = Net::SSLeay::accept($ssl) and Net::SSLeay::die_if_ssl_error('ssl accept');

    $self->set_writer_func(sub {
        my ($bref, $to_write, $offset) = @_;

        # we can't write a lot or we get some SSL non-blocking error
        $to_write = 4096 if $to_write > 4096;

        my $str = substr($$bref, $offset, $to_write);
        warn "Writing over SSL (to_write=$to_write, off=$offset): $str\n";
        my $written = Net::SSLeay::write($ssl, $str);
        warn "  returned = $written\n";
        if ($written == -1) {
            my $err = Net::SSLeay::get_error($ssl, $written);
            my $errstr = Net::SSLeay::ERR_error_string($err);
            warn "err = $err, $errstr\n";
            Net::SSLeay::print_errs("SSL_write");
            die "we died writing\n";
        }

        return $written;
    });

    #warn "socked pre-SSL is: $self->{sock}\n";
    #my $rv = IO::Socket::SSL->start_SSL($self->{sock}); #, { SSL_verify_mode => 0x00 });
    #my $fileno = fileno $self->{sock};
    #warn "was fileno = $fileno\n";
    #my $sym = gensym();
    #my $ssl = IO::Socket::SSL->new_from_fd($fileno);
    #warn " got ssl = $ssl, error = $@ / $!\n";
    #warn " fileno = ", fileno($ssl), "\n";
    #  my $tied = tie($sym, "DJabberd::SSL");
    # warn "Started SSL with $self->{sock}, tied = $tied\n";
}

# from the JabberHandler
sub process_iq {
    my ($self, $iq) = @_;

    foreach my $meth (
                      \&process_iq_getauth,
                      \&process_iq_setauth,
                      \&process_iq_getroster,
                      ) {
        return if $meth->($self, $iq);
    }

    warn "Unknown IQ packet: " . Dumper($iq);
}

sub jid {
    my $self = shift;
    my $jid = $self->{username} . '@' . $self->{server_name};
    $jid .= "/$self->{resource}" if $self->{resource};
    return $jid;
}

sub process_message {
    my ($self, $msg) = @_;

    my $to = $msg->to;
    my $client = Client->find_client($to);
    warn "CLIENT of jid '$to' = $client\n";
    if ($client) {
        $client->send_message($self, $msg);
    } else {
        my $self_jid = $self->jid;
        # FIXME: keep message body better
        $self->write("<message from='$to' to='$self_jid' type='error'><x xmlns='jabber:x:event'><composing/></x><body>lost</body><html xmlns='http://jabber.org/protocol/xhtml-im'><body xmlns='http://www.w3.org/1999/xhtml'>lost</body></html><error code='404'>Not Found</error></message>");
    }
}

sub send_message {
    my ($self, $from, $msg) = @_;

    my $from_jid = $from->jid;
    my $my_jid   = $self->jid;

    my $message_back = "<message type='chat' to='$my_jid' from='$from_jid'>" . $msg->innards_as_xml . "</message>";
    warn "Message from $from_jid to $my_jid: $message_back\n";
    $self->write($message_back);
}

sub process_iq_getroster {
    my ($self, $iq) = @_;
    # try and match this:
    # <iq type='get' id='gaim146ab72d'><query xmlns='jabber:iq:roster'/></iq>
    return 0 unless $iq->type eq "get";
    my $qry = $iq->first_element
        or return;
    return 0 unless $qry->element eq "{jabber:iq:roster}query";

    my $to = $self->jid;
    my $id = $iq->id;

    my $items = "";
    my $friends = LWP::Simple::get("http://www.livejournal.com/misc/fdata.bml?user=" . $self->{username});
    foreach my $line (sort split(/\n/, $friends)) {
        next unless $line =~ m!> (\w+)!;
        my $fuser = $1;
        $items .= "<item jid='$fuser\@$self->{server_name}' name='$fuser' subscription='both'><group>Friends</group></item>\n";
    }

    my $roster_res = qq{
<iq to='$to' type='result' id='$id'>
     <query xmlns='jabber:iq:roster'>
        $items
     </query>
</iq>
 };

    #warn "ROSTER FOR $self: {$roster_res}\n";

    $self->write($roster_res);

    return 1;
}

sub process_iq_getauth {
    my ($self, $iq) = @_;
    # try and match this:
    # <iq type='get' id='gaimf46fbc1e'><query xmlns='jabber:iq:auth'><username>brad</username></query></iq>
    return 0 unless $iq->type eq "get";

    my $query = $iq->query
        or return 0;
    my $child = $query->first_element
        or return;
    return 0 unless $child->element eq "{jabber:iq:auth}username";

    my $username = $child->first_child;
    die "Element in username field?" if ref $username;

    my $id = $iq->id;

    $self->write("<iq id='$id' type='result'><query xmlns='jabber:iq:auth'><username>$username</username><digest/><resource/></query></iq>");

    return 1;
}

sub process_iq_setauth {
    my ($self, $iq) = @_;
    # try and match this:
    # <iq type='set' id='gaimbb822399'><query xmlns='jabber:iq:auth'><username>brad</username><resource>work</resource><digest>ab2459dc7506d56247e2dc684f6e3b0a5951a808</digest></query></iq>
    return 0 unless $iq->type eq "set";
    my $id = $iq->id;

    my $query = $iq->query
        or return 0;
    my @children = $query->children;

    my $get = sub {
        my $lname = shift;
        foreach my $c (@children) {
            next unless ref $c && $c->element eq "{jabber:iq:auth}$lname";
            my $text = $c->first_child;
            return undef if ref $text;
            return $text;
        }
        return undef;
    };

    my $username = $get->("username");
    my $resource = $get->("resource");
    my $digest   = $get->("digest");

    return unless $username =~ /^\w+$/;

    my @auth_hooks = @{ $self->server->{auth_hooks} };

    my $accept = sub {
        $self->{authed}   = 1;
        $self->{username} = $username;
        $self->{resource} = $resource;

        # register
        my $sname = $self->{server_name};
        foreach my $jid ("$username\@$sname",
                         "$username\@$sname/$resource") {
            Client->register_client($jid, $self);
        }

        # FIXME: escape, or make $iq->send_good_result, or something
        $self->write(qq{<iq id='$id' type='result' />});
        return;
    };

    my $reject = sub {
        warn " BAD LOGIN!\n";
        # FIXME: FAIL
        return 1;
    };

    my $try_another;
    $try_another = sub {

        my $ah = shift @auth_hooks;
        unless ($ah) {
            $reject->();  # default policy if no auth hook responses accept
            return;
        }

        my $nullify_callback = 0;
        my $callback_called  = 0;
        # TODO: look into circular references on closures
        warn "Calling check_auth on $ah...\n";
        my $rv = $ah->check_auth($self, { username => $username, resource => $resource, digest => $digest },
                                 DJabberd::Callback->new(
                                                         _pre    => sub {
                                                             return if $nullify_callback;
                                                             $callback_called = 1;

                                                             my ($self, $meth) = @_;
                                                             warn "  $ah called callback: $meth\n";
                                                         },
                                                         decline => $try_another,
                                                         accept => sub { $accept->() },
                                                         reject => sub { $reject->() },
                                                         ));

        if (defined $rv && ! $callback_called) {
            warn "  $ah returned: $rv\n";
            $nullify_callback = 1;
            $accept->() if $rv;
            $reject->() unless $rv;
        }
    };
    $try_another->();

    return 1;  # signal that we've handled it


#    my $password_is_livejournal = sub {
#        my $good = LWP::Simple::get("http://www.livejournal.com/misc/jabber_digest.bml?user=" . $username . "&stream=" . $self->{stream_id});
#        chomp $good;
#        return $good eq $digest;
#    }

#    my $password_is_password = sub {
#        my $good = Digest::SHA1::sha1_hex($self->{stream_id} . "password");
#        return $good eq $digest;
#    };
}

# Client
sub event_read {
    my Client $self = shift;

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
    my Client $self = shift;
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
    my Client $self = shift;
    $self->write("</stream:stream>");
    $self->write(sub { $self->close; });
    # TODO: unregister client from %jid2sock
}

sub event_write {
    my $self = shift;
    $self->watch_write(0) if $self->write(undef);
}

sub close {
    my Client $self = shift;
    print "DISCONNECT: $self\n";

    if (my $ssl = $self->{ssl}) {
        Net::SSLeay::free($ssl);
    }

    $self->SUPER::close;
}


# Client
sub event_err { my $self = shift; $self->close; }
sub event_hup { my $self = shift; $self->close; }


# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

1;
