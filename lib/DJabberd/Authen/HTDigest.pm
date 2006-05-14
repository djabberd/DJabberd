package DJabberd::Authen::HTDigest;
use strict;
use base 'DJabberd::Authen';

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger;
use Digest::MD5 qw(md5_hex);
sub log {
    $logger;
}

sub set_config_htdigest {
    my ($self, $htdigest) = @_;
    $self->{htdigest} = $htdigest;
}

sub set_config_realm {
    my ($self, $realm) = @_;
    $self->{realm} = $realm;
}

sub finalize {
    my $self = shift;
    $logger->logdie("No htdigest file") unless $self->{htdigest};
    $logger->logdie("htdigest file '$self->{htdigest}' does not exist") unless -e $self->{htdigest};
    $logger->logdie("htdigest file '$self->{htdigest} not readable") unless -r $self->{htdigest};
    $logger->logdie("No realm specified") unless $self->{realm};
}

sub can_retrieve_cleartext { 0 }

sub check_cleartext {
    my ($self, $cb, %args) = @_;
    my $username = $args{username};
    my $password = $args{password};
    my $conn = $args{conn};
    unless ($username =~ /^\w+$/) {
        $cb->reject;
        return;
    }


    open(my $htdigest, "<$self->{htdigest}") || $logger->logwarn("Cannot open file '$self->{htdigest}': $!");
    while(<$htdigest>) {
        chomp;
        next unless /^$username:$self->{realm}:(.+)$/;
        my $md5_orig     = $1;
        my $md5_computed = md5_hex("$username:$self->{realm}:$password");
        if($md5_orig eq $md5_computed) {
            $cb->accept;
            $logger->debug("User '$username' successfully logged in");
            return 1;
        } else {
            $cb->reject();
            $logger->info("User '$username' denied, '$md5_orig' ne '$md5_computed'");
            return 0;
        }
    }

    $logger->info("User '$username' denied, does not exist in '$self->{htdigest}");
    $cb->reject;
    return 1;
}

1;
