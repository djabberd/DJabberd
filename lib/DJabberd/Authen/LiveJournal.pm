package DJabberd::Authen::LiveJournal;
use strict;
use base 'DJabberd::Authen';
use LWP::Simple;

sub can_check_digest { 1 }

sub check_digest {
    my ($self, $cb, %args) = @_;

    my $conn    = delete $args{'conn'}     or die;
    my $digest  = delete $args{'digest'};
    my $user    = delete $args{'username'} or die;
    my $streamid = $conn->stream_id;

    unless ($digest =~ /^\w+$/) {
        $cb->reject;
        return;
    }

    my $is_good = LWP::Simple::get("http://www.livejournal.com/misc/jabber_digest.bml?user=$user" .
                                   "&stream=$streamid&digest=$digest");
    if ($is_good =~ /^GOOD/) {
        $cb->accept;
    } else {
        $cb->reject;
    }
}

1;
