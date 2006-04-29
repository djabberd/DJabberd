package DJabberd::PresenceChecker::Local;
use strict;
use warnings;
use base 'DJabberd::PresenceChecker';

sub check_presence {
    my ($self, $cb, $jid, $adder) = @_;

    my $vhost = $self->vhost;

    my $map = DJabberd::Presence->local_presence_info($jid);
    foreach my $fullstr (keys %$map) {
        my $jid  = DJabberd::JID->new($fullstr);

        # see if $fullstr is still connected, otherwise ignore.
        # ideally on disconnect/timeout, the local_presence_info
        # would be cleaned, but let's not trust that for now.
        $vhost->find_jid($jid) or next;

        my $pres = $map->{$fullstr};
        $adder->($jid, $pres);
    }

    $cb->done;
}

1;
