package DJabberd::PresenceChecker;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::Plugin';

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub vhost { $_[0]->{vhost} }

sub register {
    my ($self, $vhost) = @_;

    $self->{vhost} = $vhost;

    # this is an odd hook, in that it wants to be called a lot, but the
    # normal hook chain system doesn't support that, so instead
    # this provides a cleaner interface for subclasses, which just call
    # 'add' and 'done', and this takes care of the ugliness of calling
    # the $add_cb callback.
    $vhost->register_hook("PresenceCheck", sub {
        my (undef, $cb, $jid, $add_cb) = @_;
        # cb can 'decline' only

        my $cb2 = DJabberd::Callback->new(
                                          done     => sub { $cb->decline },
                                          decline  => sub { $cb->decline },
                                          declined => sub { $cb->decline },
                                          );

        $self->check_presence($cb2, $jid, $add_cb);

    });
}

# override this.
sub check_presence {
    my ($self, $cb, $jid, $add_cb) = @_;
    # cb can only '->done/decline'
    $cb->done;
}

1;
