package DJabberd::SASL::AuthenSASL;

use strict;
use warnings;
use base qw/DJabberd::SASL/;

use DJabberd::SASL::Connection::External;

sub set_config_mechanisms {
    my ($self, $val) = @_;
    $self->{mechanisms} = { map { uc $_ => 1 } split /\s+/, ($val || "") };
}

sub set_config_extlooseverifys2s {
    my ($self, $val) = @_;
    $self->{ext_loosessl} = DJabberd::Util::as_bool($val);
}

sub mechanisms {
    my $plugin = shift;
    return $plugin->{mechanisms} || {};
}

sub register {
    my ($plugin, $vhost) = @_;
    $plugin->SUPER::register($vhost);

    $vhost->register_hook("SendFeatures", sub {
        my ($vh, $cb, $conn) = @_;
        return $cb->decline if($conn->vhost->require_ssl and (!$conn->is_server && !$conn->ssl));
        if (my $sasl_conn = $conn->sasl) {
            return $cb->decline if ($sasl_conn->is_success);
        }
        my @mech = grep {$_ ne 'EXTERNAL'} $plugin->mechanisms_list;
        my $xml_mechanisms =
            "<mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>";
        if($plugin->mechanisms->{EXTERNAL} && ($conn->ssl || 0) > 0) {
            DJabberd::SASL::Connection::External->new($conn)
                unless($conn->sasl);
            if($conn->sasl && $conn->sasl->isa('DJabberd::SASL::Connection::External')) {
                $xml_mechanisms .= "<mechanism>EXTERNAL</mechanism>";
            }
        }
	my @plus = grep {$_ =~ /^SCRAM-.+-PLUS$/}@mech;
	my @rest = grep {$_ !~ /^SCRAM-.+-PLUS$/}@mech;
	if (@plus && ($conn->ssl || 0) > 0) {
	    my $buf;
	    my $rv = Net::SSLeay::session_reused($conn->ssl);
	    if($rv) {
		$rv = Net::SSLeay::get_finished($conn->ssl, $buf);
	    } else {
		$rv = Net::SSLeay::get_peer_finished($conn->ssl, $buf);
	    }
	    if($rv > 0) {
		$conn->{bindings}->{tls_unique} = $buf;
	    } else {
		$conn->log->debug("Failed to obtain unique bindings: $rv");
		Net::SSLeay::die_if_ssl_error("tls-unique");
	    }
	    $rv = Net::SSLeay::get_certificate($conn->ssl);
	    if($rv) {
		my $obj = Net::SSLeay::P_X509_get_signature_alg($rv);
		my $alg = Net::SSLeay::OBJ_obj2txt($obj);
		my $md;
		if($alg =~ /^(sha1|md5)/) {
		    $md = Net::SSLeay::EVP_sha256();
		} elsif($alg =~ /^(sha\d+)/) {
		    $md = Net::SSLeay::EVP_get_digestbyname($1);
		}
		if($md) {
		    $buf = Net::SSLeay::X509_digest($rv, $md);
		    $conn->{bindings}->{tls_server_end_point} = $buf if($buf);
		} else {
		    $conn->log->debug("Unknown certificate algorithm: $alg/$1");
		}
	    } else {
		$conn->log->debug("Cannot obtain TLS connection certificate");
	    }
	    $buf = Net::SSLeay::export_keying_material($conn->ssl, 32, "EXPORTER-Channel-Binding", "");
	    if($buf) {
		$conn->{bindings}->{tls_exporter} = $buf;
	    } else {
		$conn->log->debug("Cannot obtain Exporter binding");
	    }
	    if($conn->{bindings} && grep{$_}values(%{$conn->{bindings}})) {
		$xml_mechanisms .= join"",map{"<mechanism>$_</mechanism>"}@plus;
		$xml_mechanisms .= "<sasl-channel-binding xmlns='urn:xmpp:sasl-cb:0'>";
		$xml_mechanisms .= join("",map{"<channel-binding type='$_'/>"}
						map{y/_/-/;$_}
							grep{$conn->{bindings}->{$_}}
								keys(%{$conn->{bindings}}));
		$xml_mechanisms .= "</sasl-channel-binding>";
	    } else {
		$conn->log->debug("Suppressing mechs[no-cb]: ".join(", ",@plus));
	    }
	} elsif(@plus) {
	    $conn->log->debug("Suppressing mech[no-ssl]: ".join(", ",@plus));
	} else {
	    if(ref($conn->{bindings}) && keys(%{$conn->{bindings}})) {
		# Disable bindings as we are not advertising -PLUS
		$conn->{bindings} = undef;
	    }
	}
        $xml_mechanisms .= join "", map { "<mechanism>$_</mechanism>" } @rest;
        $xml_mechanisms .= "<optional/>" if $plugin->is_optional;
        $xml_mechanisms .= "</mechanisms>";
        $cb->stanza($xml_mechanisms);
    });
    $vhost->register_hook("CheckCert", sub {
	my ($vh,$cb,$c,$ok,$cn,$depth,$err,$crt) = @_;
	unless($ok) {
	    if($c->is_server && $plugin->{ext_loosessl}) {
	        $DJabberd::Plugin::logger->debug("Passing S2S Cert CN=$cn at depth=$depth: $err");
		return $cb->pass;
	    } else {
	        $DJabberd::Plugin::logger->debug("Bad Cert CN=$cn at depth=$depth: $err");
            }
	}
	$cb->decline;
    }) if($plugin->mechanisms->{EXTERNAL});
}

##
# RFC 6120 Conformance Requirements [section 15] mandates support for SASL
# SCRAM-SHA-1[-PLUS] at the least for both client and server. Authen::SASL
# does not support it so let's patch it up
package Authen::SASL::Perl::SCRAM_SHA_1_PLUS;
use strict;
use warnings;
use utf8;
use base 'Authen::SASL::Perl';
use Net::SSLeay;
use Digest::SHA;
use MIME::Base64 qw/encode_base64url encode_base64 decode_base64/;
use DJabberd::JID;

# MonkeyPathing Authen::SASL
$INC{'Authen/SASL/Perl/SCRAM_SHA_1_PLUS.pm'} = __FILE__;

sub mechanism { "SCRAM-SHA-1-PLUS" }
sub _order { 5 }

my %secflags = (
  noplaintext => 1,
  noanonymous => 1,
);
sub _secflags {
  shift;
  scalar grep { $secflags{$_} } @_;
}

sub _init {
    my ($class, $self) = @_;
    bless $self, $class;

    # 128biit seems to be a good half-entropy
    my $rnd = $self->rnd(16);
    if($rnd) {
	$self->property('_nonce', encode_base64url($rnd));
	return $self;
    }
}

sub _init_server {
    my ($self, $opts) = @_;
    $self->{tlsbinndings} = ($opts->{tlsbindings} || 0) if(ref($opts) eq 'HASH');
}

sub can_bind {
    my ($self) = @_;
    return ($self->{tlsbindings} || 0);
}

sub rnd {
    my ($self, $len) = @_;
    my ($rnd, $rv);
    $rv = Net::SSLeay::RAND_bytes($rnd, $len);
    if($rv) {
	return $rnd;
    }
}

sub _encode {
    my $n = DJabberd::JID::saslprep($_[0]);
    return undef unless($n);
    $n =~ s/,/=2c/g;
    $n =~ s/=/=3d/g;
    return $n;
}

sub _decode {
    my $n = DJabberd::JID::saslprep($_[0]);
    return undef unless($n);
    $n =~ s/=2c/,/gi;
    $n =~ s/=3d/=/gi;
    return $n;
}

sub client_start {
    my ($self,$cb_type) = @_;

    $self->set_error(1);
    my $user = $self->_call('user');
    return 'Missing username' unless($user);
    $user = _encode($user);
    return 'Invalid username' unless($user);

    my $cb_data = $self->_call('binding',$cb_type);
    my $gs2_flag;
    if($cb_data) {
	$gs2_flag = "p=$cb_type";
    } elsif(defined $cb_type) {
	$gs2_flag = 'y,,';
	$cb_data = "";
    } else {
	$gs2_flag = 'n,,';
	$cb_data = "";
    }

    $self->set_error(0);
    my $client_first_bare = "n=$user,r=".$self->property('_nonce');
    $self->property('gs2_flag' => $gs2_flag);
    $self->property("cb_data" => $cb_data);
    $self->property('client_first_bare' => $client_first_bare);
    return $gs2_flag.$client_first_bare;
}

sub server_start {
    my ($self,$auth,$cb) = @_;

    # presumption of error
    $self->set_error(1);

    # Essentials
    return $cb->('Internal Server Error') unless($self->callback('getsecret'));
    return $cb->('Empty auth request') unless($auth);

    my @gs = split(',',$auth);
    return $cb->('Malformed auth request') if($#gs < 3);

    # binding mangling, bail
    return $cb->('Channel binding downgrade') if($self->can_bind && $gs[0] eq 'y');
    my $cb_data = '';
    if($gs[0] =~ /^p=(.+)/) {
	$cb_data = $self->_call('getbinding',$1);
	return $cb->('Unsupported channel binding type') unless($cb_data);
    }

    return $cb->('Invalid or missing authn identity') unless($gs[2] =~ /^n=(.+)/);

    my $user = _decode($1);
    return $cb->('Invalid or empty user name') unless($user);

    return $cb->('Invalid or missing random nonce') unless($gs[3] =~ /^r=(.+)/);
    return $cb->('Unsupported Digest Algorithm') unless($self->hash("hush"));

    # Fill up the context and dash for the pass
    #$self->property('user' => $user);
    $self->property('cb_data' =>$cb_data);
    $self->property('c_nonce' => $1);
    $self->property('gs2_flag' => $gs[0].",".$gs[1].",");
    $self->property('client_first_bare' => $gs[2].','.$gs[3]);
    $self->_call('getsecret',{user=>$user}, sub { $cb->($self->server_continue(shift, $user))});
}

sub server_continue {
    my ($self, $pass, $user) = @_;

    return 'User not found or empty password' unless($pass);

    my ($salt, $iter, $stored_key, $server_key);
    if($pass =~ /(\d{4,8}),([A-Za-z0-9+\/]{6,}={0,3}),([A-Za-z0-9+\/]{6,}={0,3}),([A-Za-z0-9+\/]{6,}={0,3})/) {
	# Use pre-salted derived keys
	$iter = 0 + $1;
	$salt = decode_base64($2);
	$stored_key = decode_base64($3);
	$server_key = decode_base64($4);
    } else {
	# Generating new derived keys with random salt
	$iter = 8192;
	$salt = $self->rnd(8);
	my $npwd = DJabberd::JID::saslprep($pass);
	return 'Password contains prohibited UTF8 codepoints: '.$@
	    unless($npwd);
	my $salted_pwd = $self->hi($pass, $salt, $iter);
	my $client_key = $self->hmac($salted_pwd, "Client Key");
	$stored_key = $self->hash($client_key);
	$server_key = $self->hmac($salted_pwd, "Server Key");
    }
    # Clear to continue
    $self->set_error(0);
    $self->{answer}{user} = $user;
    my $server_first = 'r='.$self->property('c_nonce').$self->property('_nonce')
	    .',s='.encode_base64($salt,'').",i=$iter";
    $self->property("stored_key" => $stored_key);
    $self->property("server_key" => $server_key);
    $self->property('server_first' => $server_first);
    return $server_first;
}

##
# Wipe the state clean
sub reset {
    my ($self) = @_;
    $self->property('_nonce' => undef);
    $self->property('cb_data' => undef);
    $self->property('gs2_flag' => undef);
    $self->property('c_nonce' => undef);
    $self->property('client_first_bare' => undef);
    $self->property('server_first' => undef);
    $self->property('stored_key' => undef);
    $self->property('server_key' => undef);
    $self->property('server_sig' => undef);
    $self->set_error(undef);
    $self->{answer} = {};
}

# U1		  := HMAC(str, salt + INT(1))
# U2		  := HMAC(str, U1)
# Ui		  := HMAC(str, Ui-1)
# Hi(str, salt, i):= U1 XOR U2 XOR ... XOR Ui
# SaltedPassword  := Hi(Normalize(password), salt, i)
# ClientKey       := HMAC(SaltedPassword, "Client Key")
# StoredKey       := H(ClientKey)
# AuthMessage     := client-first-message-bare + ","
#		   + server-first-message + ","
#		   + client-final-message-without-proof
# ClientSignature := HMAC(StoredKey, AuthMessage)
# ClientProof     := ClientKey XOR ClientSignature
# ClientKey	  := ClientProof XOR ClientSignature
# ServerKey       := HMAC(SaltedPassword, "Server Key")
# ServerSignature := HMAC(ServerKey, AuthMessage)
#
# DoveAdm PW SCRAM Scheme
# {SCHEME},iter,b64(salt),b64(StoredKey),b64(ServerKey)


sub hmac {
    my ($self, $key, $data) = @_; # Note argument swap
    return $self->{_hmac}->($data, $key) if($self->{_hmac});

    my $mech = $self->mechanism();
    if(index($mech, "SHA-512", 6)==6) {
	$self->{_hmac} = \&Digest::SHA::hmac_sha512;
    } elsif(index($mech, "SHA-256", 6)==6) {
	$self->{_hmac} = \&Digest::SHA::hmac_sha256;
    } elsif(index($mech, "SHA-1", 6) == 6) {
	$self->{_hmac} = \&Digest::SHA::hmac_sha1;
    } else {
	$self->{_hmac} = sub { undef };
    }
    return $self->{_hmac}->($data, $key);
}
sub hash {
    my ($self, $data) = @_;
    return $self->{_hash}->($data) if($self->{_hash});

    my $mech = $self->mechanism();
    if(index($mech, "SHA-512", 6)==6) {
	$self->{_hash} = \&Digest::SHA::sha512;
    } elsif(index($mech, "SHA-256", 6)==6) {
	$self->{_hash} = \&Digest::SHA::sha256;
    } elsif(index($mech, "SHA-1", 6) == 6) {
	$self->{_hash} = \&Digest::SHA::sha1;
    } else {
	$self->{_hash} = sub { undef };
    }
    return $self->{_hash}->($data);
}

sub hi {
    my ($self, $data, $salt, $iter) = @_;
    my $one = pack('N',1); # "\0\0\0\1";
    my $U = $self->hmac($data, $salt.$one);
    my $Hi = $U;
    for my $i (2..$iter) {
	$U = $self->hmac($data, $U);
	$Hi ^= $U;
    }
    return $Hi;
}

sub client_step {
    my ($self,$server_first) = @_;

    return $self->client_last($server_first) if($self->property('server_sig'));

    $self->set_error(1);
    return 'Malformed challenge'
	unless($server_first =~ /r=([^,]+),s=([^,]+),i=(\d+)$/);
    my ($nonce, $salt, $iter) = ($1, decode_base64($2), int($3));

    return 'Tampered Nonce' unless(rindex($nonce, $self->property('_nonce'), 0) == 0);
    return 'Too small iteration count' if(int($iter) < 4096);
    return 'Empty or small salt string' unless($salt && length($salt)>3);
    $self->set_error(0);

    my $c = encode_base64($self->property("gs2_flag").$self->property("cb_data"),'');
    my $client_last_bare = "c=$c,r=$nonce";
    my $salted_pwd = $self->hi($self->_call('pass'), $salt, $iter);
    my $client_key = $self->hmac($salted_pwd, "Client Key");
    my $stored_key = $self->hash($client_key);
    my $auth_msg = $self->property("client_first_bare").",$server_first,$client_last_bare";
    my $client_sig = $self->hmac($stored_key, $auth_msg);
    my $client_prf = $client_key ^ $client_sig;
    my $server_key = $self->hmac($salted_pwd, "Server Key");
    my $server_sig = $self->hmac($server_key, $auth_msg);
    $self->property("server_sig" => $server_sig);
    return "$client_last_bare,p=".encode_base64($client_prf,'');
}

sub server_step {
    my ($self, $client_last, $cb) = @_;

    $self->set_error(1);
    return $cb->('Malformed packet: parse') unless($client_last =~ /c=([^,]+),r=([^,]+),p=([^,]+)/);

    my $stored_key = $self->property('stored_key');
    return $cb->('Malformed packet: state') unless($stored_key);

    my ($cb_proof, $nonce, $cl_proof) = ($1, $2, decode_base64($3));
    return $cb->('Authentication Failed: nonce') unless($nonce eq $self->property('c_nonce').$self->property('_nonce'));
    my $our_cb = encode_base64($self->property('gs2_flag').$self->property('cb_data'), '');
    return $cb->('Authentication Failed: cbind') unless($cb_proof eq $our_cb);

    my $auth_msg = $self->property('client_first_bare').','.$self->property('server_first').",c=$cb_proof,r=$nonce";
    my $client_sig = $self->hmac($stored_key, $auth_msg);
    my $client_key = $client_sig ^ $cl_proof;
    return $cb->('Authentication Failed: pass') unless($stored_key eq $self->hash($client_key));

    my $server_sig = $self->hmac($self->property('server_key'), $auth_msg);
    $self->set_error(undef);
    $self->set_success();
    $cb->('v='.encode_base64($server_sig,''));
    $self->reset();
}

sub client_last {
    my ($self,$server_last) = @_;

    $self->set_error(1);
    return 'Malformed packet: parse' unless($server_last =~ /v=([^,]+)/);
    my $server_sig = decode_base64($1);
    return 'Malformed packet: data' unless($server_sig eq $self->property('server_sig'));
    $self->reset();
    $self->set_success();
}

package Authen::SASL::Perl::SCRAM_SHA_1;
use strict;
use warnings;
use base 'Authen::SASL::Perl::SCRAM_SHA_1_PLUS';
sub mechanism { "SCRAM-SHA-1" }
sub _order { 4 }
$INC{'Authen/SASL/Perl/SCRAM_SHA_1.pm'} = __FILE__;

package Authen::SASL::Perl::SCRAM_SHA_256_PLUS;
use strict;
use warnings;
use base 'Authen::SASL::Perl::SCRAM_SHA_1_PLUS';
sub mechanism { "SCRAM-SHA-256-PLUS" }
sub _order { 7 }
$INC{'Authen/SASL/Perl/SCRAM_SHA_256_PLUS.pm'} = __FILE__;

package Authen::SASL::Perl::SCRAM_SHA_256;
use strict;
use warnings;
use base 'Authen::SASL::Perl::SCRAM_SHA_1_PLUS';
sub mechanism { "SCRAM-SHA-256" }
sub _order { 6 }
$INC{'Authen/SASL/Perl/SCRAM_SHA_256.pm'} = __FILE__;

package Authen::SASL::Perl::SCRAM_SHA_512_PLUS;
use strict;
use warnings;
use base 'Authen::SASL::Perl::SCRAM_SHA_1_PLUS';
sub mechanism { "SCRAM-SHA-512-PLUS" }
sub _order { 9 }
$INC{'Authen/SASL/Perl/SCRAM_SHA_512_PLUS.pm'} = __FILE__;

package Authen::SASL::Perl::SCRAM_SHA_512;
use strict;
use warnings;
use base 'Authen::SASL::Perl::SCRAM_SHA_1_PLUS';
sub mechanism { "SCRAM-SHA-512" }
sub _order { 8 }
$INC{'Authen/SASL/Perl/SCRAM_SHA_512.pm'} = __FILE__;

1;

__END__

=head1 NAME

DJabberd::SASL::AuthenSASL - SASL Negotiation using Authen::SASL

=head1 DESCRIPTION

This plugin provides straightforward support for SASL negotiations inside
DJabberd using L<Authen::SASL> (Authen::SASL::Perl, for now). It compliments
the now deprecated I<iq-auth> authentication (XEP-0078).

The recommended usage is to use STARTTLS and SASL-PLAIN.

=head1 SYNOPSIS

    <VHost yann.cyberion.net>
        <Plugin DJabberd::SASL::AuthenSASL>
            Optional   yes
            Mechanisms PLAIN LOGIN DIGEST-MD5
        </Plugin>
    </VHost>

=head1 DESCRIPTION

Only PLAIN LOGIN and DIGEST-MD5 mechanisms are supported for now (same than
in L<Authen::SASL>. DIGEST-MD5 only supports C<auth> qop (quality of
protection), so it's strongly advised to throw TLS into the mix, and not 
solely rely on DIGEST-MD5 (as opposed to C<auth-int> and C<auth-conf>).

When using TLS with EXTERNAL method make sure you supply valid CA file or path
to the SSL layer, since it will enable peer certificate verification. Otherwise
you may enable C<ExtLooseVerifyS2S> option to still accept invalid certificates
for server connections. For invalid certificates EXTERNAL method will never be
enabled. Other plugins though may override validity of the certificates.

=head1 COPYRIGHT

(c) 2009 Yann Kerherve

This module is part of the DJabberd distribution and is covered by the
distribution's overall licence.

=cut

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:
