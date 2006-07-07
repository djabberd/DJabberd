package DJabberd::PresenceChecker::Dummy;
use strict;
use warnings;
use base 'DJabberd::PresenceChecker';

sub check_presence {
    my ($self, $cb, $jid, $adder) = @_;

    my $vhost = $self->vhost;


    if ($jid->node =~/^dummy_/) {
        $adder->($jid, DJabberd::Presence->new('jabber:client', 'presence', { '{}from' => $jid}, []));
        $cb->done;
    } else {
        $cb->reject;
    }
}

1;
