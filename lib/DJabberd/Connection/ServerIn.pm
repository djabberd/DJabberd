package DJabberd::Connection::ServerIn;
use strict;
use base 'DJabberd::Connection';
use fields ('announced_dialback');

use DJabberd::Stanza::DialbackResult;

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

sub process_stanza_builtin {
    my ($self, $node) = @_;

    my %stanzas = (
                   "{jabber:server:dialback}result" => "DJabberd::Stanza::DialbackResult",
                   );

    my $class = $stanzas{$node->element};
    unless ($class) {
        return $self->SUPER::process_stanza_builtin($node);
    }

    my $obj = $class->new($node);
    $obj->process($self);
}

sub dialback_verify_valid {
    my $self = shift;
    my %opts = @_;

    my $res = qq{<db:result from='$opts{recv_server}' to='$opts{orig_server}' type='valid'/>};
    warn "Dialback verify valid for $self.  from=$opts{recv_server}, to=$opts{orig_server}: $res\n";
    $self->write($res);
}

sub dialback_verify_invalid {
    my ($self, $reason) = @_;
    warn "Dialback verify invalid for $self, reason: $reason\n";
    $self->close_stream;
}


1;
