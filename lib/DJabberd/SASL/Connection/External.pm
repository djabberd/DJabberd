package DJabberd::SASL::Connection::External;
use strict;
use warnings;
use base 'DJabberd::SASL::Connection';

sub new {
    my $class = shift;
    my $conn = shift;
    my $crt = Net::SSLeay::get_peer_certificate($conn->ssl);
    if($crt) {
        my $res = Net::SSLeay::get_verify_result($conn->ssl);
        if($res == &Net::SSLeay::X509_V_OK) {
            return $conn->{sasl} = bless {
		    crt => $crt,
		    res => $res,
		    id => undef
                }, ref $class || $class;
        }
        Net::SSLeay::X509_free($crt);
        $conn->log->info("Cannot enable EXTERNAL SASL for conn ".$conn->{id}
                        .": ".Net::SSLeay::X509_verify_cert_error_string($res));
    }
}

sub DESTROY {
    Net::SSLeay::X509_free($_[0]->{crt});
}

sub set_id {
    my $self = shift;
    $self->{id} = shift;
}

sub id { return $_[0]->{id} }
sub res { return $_[0]->{res} }
sub crt { return $_[0]->{crt} }
sub is_success { return $_[0]->{id} }

sub srv_auth {
    my $self = shift;
    my $host = shift;
    return Net::SSLeay::X509_check_host($self->{crt}, $host, 0)
        if($host && $host =~ /^[a-zA-Z0-9.-]{1,255}$/);
    return -1;
}
sub usr_auth {
    my $self = shift;
    my $user = shift;
    my $vhost = shift;
    return $self->{jid}{$user} if($user && %{$self->{jid} || {}});
    return Net::SSLeay::X509_check_email($self->{crt}, $user, 0)
        if($user && $vhost->handles_jid(DJabberd::JID->new($user)));
    return 0;
}
sub usr_guess {
    my $self = shift;
    my $vhost = shift;
    my (%mail,%jid);
    unless($self->{jid} || $self->{mail}) {
        my @san = Net::SSLeay::X509_get_subjectAltNames($self->{crt});
        while(@san) {
            my $type = shift(@san);
            my $name = shift(@san);
            my $j = DJabberd::JID->new($name);
            next unless($vhost->handles_jid($j));
            if($type == 0) {
                $jid{$name} = 1;
            } elsif($type == 1) {
                $mail{$name} = 1;
            }
        }
	$self->{jid} = \%jid;
	$self->{mail} = \%mail;
    } else {
        %jid = %{$self->{jid}};
	%mail = %{$self->{mail}};
    }
    # Try to guess user or fail
    return (keys(%jid))[0] if(%jid && scalar(keys(%jid)) == 1);
    return (keys(%mail))[0] if(%mail && scalar(keys(%mail)) == 1);
    # match CN? Email? nah, let people have proper certs
    return '';
}
1;
