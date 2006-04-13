package DJabberd::Authen::StaticPassword;
use strict;
use base 'DJabberd::Authen';

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
