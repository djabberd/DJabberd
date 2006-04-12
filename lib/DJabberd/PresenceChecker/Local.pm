package DJabberd::PresenceChecker::Local;
use strict;
use warnings;
use base 'DJabberd::PresenceChecker';

sub check_presence {
    my ($self, $cb, $jid, $adder) = @_;

    my $map = DJabberd::Presence->local_presence_info($jid);
    foreach my $fullstr (keys %$map) {
        my $jid  = DJabberd::JID->new($fullstr);
        my $pres = $map->{$fullstr};
        $adder->($jid, $pres);
    }

    $cb->done;
}

1;
