package DJabberd::Connection::ServerIn;
use strict;
use base 'DJabberd::Connection';
use fields
    ('announced_dialback',
     'verified_remote_domain',  # once we know it
     );

use DJabberd::Stanza::DialbackResult;

sub peer_domain {
    my $self = shift;
    return $self->{verified_remote_domain};
}

sub on_stream_start {
    my ($self, $ss) = @_;

    if ($ss->announced_dialback) {
        $self->{announced_dialback} = 1;
        $self->start_stream_back($ss,
                                 extra_attr => "xmlns:db='jabber:server:dialback'",
                                 namespace  => 'jabber:server');
    } else {
        $self->start_stream_back($ss,
                                 namespace  => 'jabber:server');
    }
}

sub on_stanza_received {
    my ($self, $node) = @_;


    if ($self->log->is_debug) {
        local $DJabberd::ASXML_NO_TEXT = 0;
        my $as_xml = $node->as_xml;
	$self->log->debug("$self->{id} Got XML '$as_xml'");
    }

    my %class = (
                   "{jabber:server:dialback}result" => "DJabberd::Stanza::DialbackResult",
                   "{jabber:server:dialback}verify" => "DJabberd::Stanza::DialbackVerify",
                   "{jabber:server}iq"       => 'DJabberd::IQ',
                   "{jabber:server}message"  => 'DJabberd::Message',
                   "{jabber:server}presence" => 'DJabberd::Presence',
                   "{http://etherx.jabber.org/streams}features" => 'DJabberd::Stanza::StreamFeatures',
                   );

    my $class = $class{$node->element} or
        return $self->stream_error("unsupported-stanza-type", $node->element);

    # same variable as $node, but down(specific)-classed.
    my $stanza = $class->downbless($node, $self);

    $self->run_hook_chain(phase => "filter_incoming_server",
                          args  => [ $stanza ],
                          methods => {
                              reject => sub { },  # just stops the chain
                          },
                          fallback => sub {
                              $self->filter_incoming_server_builtin($stanza);
                          });
}

sub filter_incoming_server_builtin {
    my ($self, $stanza) = @_;

    unless ($stanza->acceptable_from_server($self)) {
        # FIXME: who knows.  send something else.
        $self->stream_error;
        return 0;
    }

    $self->run_hook_chain(phase => "switch_incoming_server",
                          args  => [ $stanza ],
                          methods => {
                              process => sub { $stanza->process($self) },
                              deliver => sub { $stanza->deliver($self) },
                          },
                          fallback => sub {
                              $self->switch_incoming_server_builtin($stanza);
                          });
}

sub switch_incoming_server_builtin {
    my ($self, $stanza) = @_;

    # FIXME: we want to process here.. like for presence and stuff later,
    # but for now all we care about is message delivery.  ghettos:

    if ($stanza->isa("DJabberd::Stanza::DialbackResult") ||
        $stanza->isa("DJabberd::Stanza::DialbackVerify"))
    {
        $stanza->process($self);
    } elsif ($stanza->isa("DJabberd::Presence")) {
        $stanza->process_inbound($self);
    } else {
        $stanza->deliver($self);
    }
}

sub is_server { 1 }

sub namespace {
    return "jabber:server";
}

sub dialback_verify_valid {
    my $self = shift;
    my %opts = @_;
    
    # according to page 45 of the spec we have to send the ID back
    my $res = qq{<db:verify from='$opts{recv_server}' to='$opts{orig_server}' id='$opts{id}' type='valid'/>};

    warn "Dialback verify valid for $self.  from=$opts{recv_server}, to=$opts{orig_server}: $res\n";
    $self->write($res);
}

sub dialback_verify_invalid {
    my ($self, $reason) = @_;
    warn "Dialback verify invalid for $self, reason: $reason\n";
    $self->close_stream;
}

sub dialback_result_valid {
    my $self = shift;
    my %opts = @_;

    my $res = qq{<db:result from='$opts{recv_server}' to='$opts{orig_server}' type='valid'/>};
    $self->{verified_remote_domain} = $opts{orig_server};

    warn "Dialback result valid for $self.  from=$opts{recv_server}, to=$opts{orig_server}: $res\n";
    $self->write($res);
}

sub dialback_result_invalid {
    my ($self, $reason) = @_;
    $self->log->warn("Dialback result invalid for $self, reason: $reason");
    $self->close_stream;
}


1;
