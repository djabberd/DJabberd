package DJabberd::Authen::LiveJournal;
use strict;
use base 'DJabberd::Authen';
use DJabberd::Plugin::LiveJournal;
use LWP::Simple;

sub can_check_digest { 1 }

sub check_digest {
    my ($self, $cb, %args) = @_;

    my $conn     = delete $args{'conn'}     or die;
    my $digest   = delete $args{'digest'};
    my $user     = delete $args{'username'} or die;

    my $streamid = $conn->stream_id;

    unless ($digest =~ /^\w+$/) {
        $cb->reject;
        return;
    }

    my $gc = DJabberd::Plugin::LiveJournal->gearman_client;

    # non-blocking auth lookup, using gearman.
    if ($gc) {
         $gc->add_task(Gearman::Task->new("ljtalk_auth_check" => \Storable::nfreeze([$user,$streamid,$digest,$resource, $conn->peer_ip_string]), {
            uniq        => "-",
            retry_count => 2,
            timeout     => 10,
            on_fail     => sub { $cb->reject; },
            on_complete => sub {
                my $ansref = shift;
                if ($$ansref eq "OK") {
                    $cb->accept;
                } else {
                    $cb->reject;
                }
                return;
            },
        }));
    }

    # blocking (low performance, don't use) plugin, using LWP.  ghetto.
    else {
        my $is_good = LWP::Simple::get("http://www.livejournal.com/misc/jabber_digest.bml?user=$user" .
                                       "&stream=$streamid&digest=$digest");
        if ($is_good =~ /^GOOD/) {
            $cb->accept;
        } else {
            $cb->reject;
        }
    }
}

1;
