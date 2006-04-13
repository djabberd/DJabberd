package DJabberd::Authen::LiveJournal;
use strict;
use base 'DJabberd::Authen';
use LWP::Simple;

sub new {
    my ($class, %opts) = @_;
    return bless {
        server  => delete $opts{'server'},
    }, $class;
}

sub check_auth {
    my ($self, $conn, $auth_info, $cb) = @_;

#    my $password_is_livejournal = sub {
#        my $good = LWP::Simple::get("http://www.livejournal.com/misc/jabber_digest.bml?user=" . $username . "&stream=" . $self->{stream_id});
#        chomp $good;
#        return $good eq $digest;

    my $good = Digest::SHA1::sha1_hex($conn->{stream_id} . $self->{password});
    return $good eq $auth_info->{'digest'} ? 1 : 0;
}

1;
