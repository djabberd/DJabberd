package DJabberd::Auth::StaticPassword;
use strict;
use base 'DJabberd::Auth';

sub new {
    my ($class, %opts) = @_;
    my $pass = delete $opts{'password'};
    return bless {
        password  => $pass,
    }, $class;
}

sub check_auth {
    my ($self, $conn, $auth_info, $cb) = @_;

    my $good = Digest::SHA1::sha1_hex($conn->{stream_id} . $self->{password});
    return $good eq $auth_info->{'digest'} ? 1 : 0;
}

1;
