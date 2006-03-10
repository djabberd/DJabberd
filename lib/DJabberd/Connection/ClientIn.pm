package DJabberd::Connection::ClientIn;
use strict;
use base 'DJabberd::Connection';

sub on_stream_start {
    my DJabberd::Connection $self = shift;
    my $ss = shift;
    $self->start_stream_back($ss,
                             namespace  => 'jabber:client');
}

sub incoming_stanza_hook_phases {
    return ("incoming_stanza", "incoming_client_stanza");
}

sub process_stanza_builtin {
    my ($self, $node) = @_;

    my %stanzas = (
                   "{jabber:client}iq"      => 'DJabberd::IQ',
                   "{jabber:client}message" => 'DJabberd::Message',
                   "{jabber:client}presence" => 'DJabberd::Presence',
                   );

    my $class = $stanzas{$node->element};
    unless ($class) {
        return $self->SUPER::process_stanza_builtin($node);
    }

    my $obj = $class->new($node);
    $obj->process($self);
}


1;
