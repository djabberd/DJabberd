#!/usr/bin/perl

# TODO: ignore the "     " spaces in between end/start events?  used as keep-alive
#
# TODO: server to server... port 5269

use strict;
use Carp;
use Danga::Socket;
use IO::Socket::INET;
use POSIX ();
use XML::SAX ();
use XML::SAX::Expat::Incremental 0.04;
#use XML::XPath;
#use XML::XPath::Builder;
#use XML::Filter::Tee;
use LWP::Simple;
use Digest::SHA1 qw(sha1_hex);

package DJabberd;
use strict;
use Socket qw(IPPROTO_TCP TCP_NODELAY SOL_SOCKET SOCK_STREAM);

sub new {
    my ($class, %opts) = @_;
    return bless { %opts }, $class;
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
    my $server = IO::Socket::INET->new(LocalPort => 5222,
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

        my $client = Client->new($csock);
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
            'teehandler',
            'builder',
            'parser',
            'stream_id',
            'authed',     # bool, if authenticated
            'username',   # username of user, once authenticated
            'resource',   # resource of user, once authenticated
            'server_name', # servername to send to user in stream header
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
    my Client $self = shift;
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new( @_ );

    # FIXME: circular reference from self to jabberhandler to self
    my $jabberhandler = $self->{'jabberhandler'} = JabberHandler->new($self);

    #my $tee = $self->{'teehandler'} = XML::Filter::Tee->new(
    #                                                        { Handler => $jabberhandler },
    #                                                        );

    #my $p = XML::SAX::Expat::Incremental->new( Handler => $tee );
    my $p = XML::SAX::Expat::Incremental->new( Handler => $jabberhandler );
    $self->{parser} = $p;
    $self->{server_name} = "207.7.148.210";

    warn "CONNECTION from " . $self->peer_ip_string . " == $self\n";

    return $self;
}

sub start_capturing {
    my Client $self = shift;
    my $start_data  = shift;

    my $tee = $self->{teehandler};
    my $builder = $self->{'builder'} = XML::XPath::Builder->new;

    # important for builder to go first!
    $tee->set_handlers($builder, $self->{jabberhandler});

    # can you do this?
    $builder->start_document;
    $builder->start_element($start_data);
}

sub end_capturing {
    my Client $self = shift;

    my $doc = $self->{builder}->end_document;
    $self->{builder} = undef;
    $self->{teehandler}->set_handlers($self->{jabberhandler});
    return $doc;
}

sub handle_packet {
    my ($self, $node) = @_;

    if ($node->element eq "{jabber:client}iq") {
        my $iq = XMPP::IQ->new($node);
        return $self->handle_iq($iq);
    }

    if ($node->element eq "{jabber:client}message") {
        my $iq = XMPP::Message->new($node);
        return $self->handle_message($iq);
    }

    warn "Unknown packet: " . Dumper($node);
    return;
}

# from the JabberHandler
sub handle_iq {
    my ($self, $iq) = @_;

    foreach my $meth (
                      \&handle_iq_getauth,
                      \&handle_iq_setauth,
                      \&handle_iq_getroster,
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

sub handle_message {
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

    my $message_back = "<message type='chat' from='$from_jid'>" . $msg->innards_as_xml . "</message>";
    warn "Message from $from_jid to $my_jid: $message_back\n";
    $self->write($message_back);
}

sub handle_iq_getroster {
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
    foreach my $line (split(/\n/, $friends)) {
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

    warn "ROSTER FOR $self: {$roster_res}\n";

    $self->write();

    return 1;
}

sub handle_iq_getauth {
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

    warn "Said digest only for user $username.";
    $self->write("<iq id='$id' type='result'><query xmlns='jabber:iq:auth'><username>$username</username><digest/><resource/></query></iq>");

    return 1;
}

sub handle_iq_setauth {
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

    my $password_is_livejournal = sub {
        my $good = LWP::Simple::get("http://www.livejournal.com/misc/jabber_digest.bml?user=" . $username . "&stream=" . $self->{stream_id});
        chomp $good;
        return $good eq $digest;

    };

    my $password_is_password = sub {
        my $good = Digest::SHA1::sha1_hex($self->{stream_id} . "password");
        return $good eq $digest;
    };

    unless ($password_is_password->() ||
            $password_is_livejournal->()) {
        warn " BAD LOGIN!\n";
        # FIXME: FAIL
        return 1;
    }

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

    return 1;
}

# Client
sub event_read {
    my Client $self = shift;

    my $bref = $self->read(20_000);
    return $self->close unless defined $bref;

    my $p = $self->{parser};
    print "$self parsing more... [$$bref]\n";
    eval {
        $p->parse_more($$bref);
    };
    if ($@) {
        print "disconnected $self because: $@\n";
        $self->close;
        return;
    }
    print "$self parsed\n";
}

sub start_stream {
    my Client $self = shift;
    my $id = $self->{stream_id} = Digest::SHA1::sha1_hex(rand() . rand() . rand());
    my $rv = $self->write(qq{<?xml version="1.0" encoding="UTF-8"?>
                                 <stream:stream from="$self->{server_name}" id="$id" version="1.0" xmlns:stream="http://etherx.jabber.org/streams" xmlns="jabber:client">
                                 <stream:features></stream:features>
                             });
    return;
}

sub event_write {
    my $self = shift;
    $self->watch_write(0) if $self->write(undef);
}

sub close {
    my Client $self = shift;
    print "DISCONNECT: $self\n";
    $self->SUPER::close;
}


# Client
sub event_err { my $self = shift; $self->close; }
sub event_hup { my $self = shift; $self->close; }


package JabberHandler;
use base qw(XML::SAX::Base);

sub new {
    my ($class, $client) = @_;
    my $self = $class->SUPER::new;
    $self->{"ds_client"} = $client;
    $self->{"capture_depth"} = 0;  # on transition from 1 to 0, stop capturing
    $self->{"on_end_capture"} = undef;  # undef or $subref->($doc)
    $self->{"events"} = [];  # capturing events
    return $self;
}

sub start_element {
    my $self = shift;
    my $data = shift;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, ["start_element", $data];
        $self->{capture_depth}++;
        return;
    }

    my $ds = $self->{ds_client};

    my $start_capturing = sub {
        my $cb = shift;

        $self->{"events"} = [];  # capturing events
        $self->{capture_depth} = 1;

        # capture via saving SAX events
        push @{$self->{events}}, ["start_element", $data];

        ## capture via XPath:
        #$ds->start_capturing($data);

        $self->{on_end_capture} = $cb;
        return 1;
    };

    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {

        $ds->start_stream;
        return;
    }

    return $start_capturing->(sub {
        my ($doc, $events) = @_;
        my $nodes = _nodes_from_events($events);
        $ds->handle_packet($nodes->[0]);
    });

}

sub characters {
    my ($self, $data) = @_;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, ["characters", $data];
    }
}

sub end_element {
    my ($self, $data) = @_;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, ["end_element", $data];
        $self->{capture_depth}--;
        return if $self->{capture_depth};
        my $doc = undef; #$self->{ds_client}->end_capturing;
        if (my $cb = $self->{on_end_capture}) {
            $cb->($doc, $self->{events});
        }
        return;
    }

    #print Dumper("END", $data);
}

sub _nodes_from_events {
    my $evlist = shift;  # don't modify
    #my $tree = ["namespace", "element", \%attr, [ <children>* ]]

    my @events = @$evlist;  # our copy
    my $nodelist = [];

    my $handle_chars = sub {
        my $ev = shift;
        my $text = $ev->[1]{Data};
        if (@$nodelist == 0 || ref $nodelist->[-1]) {
            push @$nodelist, $text;
        } else {
            $nodelist->[-1] .= $text;
        }
    };

    my $handle_element = sub {
        my $ev = shift;
        my $depth = 1;
        my @children = ();
        while (@events && $depth) {
            my $child = shift @events;
            push @children, $child;

            if ($child->[0] eq "start_element") {
                $depth++;
                next;
            } elsif ($child->[0] eq "end_element") {
                $depth--;
                next if $depth;
                pop @children;  # this was our own element
            }
        }
        die "Finished events without reaching depth 0!" if !@events && $depth;

        my $ns = $ev->[1]{NamespaceURI};

        # clean up the attributes from SAX
        my $attr_sax = $ev->[1]{Attributes};
        my $attr = {};
        foreach my $key (keys %$attr_sax) {
            my $val = $attr_sax->{$key}{Value};
            my $fkey = $key;
            if ($fkey =~ s!^\{\}!!) {
                next if $fkey eq "xmlns";
                $fkey = "{$ns}$fkey";
            }
            $attr->{$fkey} = $val;
        }

        my $localname = $ev->[1]{LocalName};
        my $ele = XML::Element->new(["{$ns}$localname",
                                     $attr,
                                     _nodes_from_events(\@children)]);
        push @$nodelist, $ele;
    };

    while (@events) {
        my $ev = shift @events;
        if ($ev->[0] eq "characters") {
            $handle_chars->($ev);
            next;
        }

        if ($ev->[0] eq "start_element") {
            $handle_element->($ev);
            next;
        }

        die "Unknown event in stream: $ev->[0]\n";
    }
    return $nodelist;
}


package XML::Element;

use constant ELEMENT  => 0;
use constant ATTRS    => 1;
use constant CHILDREN => 2;

sub new {
    my ($class, $node) = @_;
    return bless $node, $class;
}

sub children {
    my $self = shift;
    return @{ $self->[CHILDREN] };
}

sub first_child {
    my $self = shift;
    return @{ $self->[CHILDREN] } ? $self->[CHILDREN][0] : undef;
}

sub first_element {
    my $self = shift;
    foreach my $c (@{ $self->[CHILDREN] }) {
        return $c if ref $c;
    }
    return undef;
}

sub attr {
    return $_[0]->[ATTRS]{$_[1]};
}

sub attrs {
    return $_[0]->[ATTRS];
}

sub element {
    return $_[0]->[ELEMENT] unless wantarray;
    my $el = $_[0]->[ELEMENT];
    $el =~ /^\{(.+)\}(.+)/;
    return ($1, $2);

}

sub as_xml {
    my $self = shift;
    my $nsmap = shift || {};  # localname -> uri, uri -> localname
    my $def_ns = shift;

    my ($ns, $el) = $self->element;

    # FIXME: escaping
    my $attr_str = "";
    my $attr = $self->attrs;
    foreach my $k (keys %$attr) {
        my $value = $attr->{$k};
        $k =~ s!^\{(.+)\}!!;
        my $ns = $1;
        $attr_str .= " $k='" . main::exml($value) . "'";
    }

    my $xmlns = $ns eq $def_ns ? "" : " xmlns='$ns'";
    my $innards = $self->innards_as_xml($nsmap, $ns);
    return length $innards ?
        "<$el$xmlns$attr_str>$innards</$el>" :
        "<$el$xmlns$attr_str/>";
}

sub innards_as_xml {
    my $self = shift;
    my $nsmap = shift || {};
    my $def_ns = shift;

    my $ret = "";
    foreach my $c ($self->children) {
        if (ref $c) {
            $ret .= $c->as_xml($nsmap, $def_ns);
        } else {
            $ret .= $c;
        }
    }
    return $ret;
}

package XMPP::IQ;
use base 'XML::Element';

sub id {
    return $_[0]->attr("{jabber:client}id");
}

sub type {
    return $_[0]->attr("{jabber:client}type");
}

sub query {
    my $self = shift;
    my $child = $self->first_element
        or return;
    print "CHILD = $child\n";
    my $ele = $child->element
        or return;
    return undef unless $child->element =~ /\}query$/;
    return $child;
}

package XMPP::Message;
use base 'XML::Element';

sub to {
     return $_[0]->attr("{jabber:client}to");
}

sub from {
     return $_[0]->attr("{jabber:client}from");
}

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

1;
