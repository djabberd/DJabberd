package DJabberd::Connection::OldSSLClientIn;
use strict;
use base 'DJabberd::Connection::ClientIn';
use DJabberd::Stanza::StartTLS;

use Net::SSLeay;

use constant SSL_MODE_ENABLE_PARTIAL_WRITE       => 1;
use constant SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER => 2;
use constant SSL_MODE_AUTO_RETRY                 => 4;

sub new {
    my ($class, $sock, $server) = @_;
    my $self = $class->SUPER::new($sock, $server);

    my $ctx = Net::SSLeay::CTX_new()
        or die("Failed to create SSL_CTX $!");

    # compared to the StartTLS, we specifically do not insist on TLS here.
    # let client do SSL 2/3/whatever.  TODO: perhaps force SSL v3?
    # $Net::SSLeay::ssl_version = 10; # Insist on TLSv1

    Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL)
        and Net::SSLeay::die_if_ssl_error("ssl ctx set options");

    Net::SSLeay::CTX_set_mode($ctx, SSL_MODE_ENABLE_PARTIAL_WRITE)
        and Net::SSLeay::die_if_ssl_error("ssl ctx set options");

    # Following will ask password unless private key is not encrypted
    Net::SSLeay::CTX_use_RSAPrivateKey_file ($ctx, $server->ssl_private_key_file, #  server-key.pem',
                                             &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("private key");

    Net::SSLeay::CTX_use_certificate_file ($ctx, $server->ssl_cert_file, # 'server-cert.pem',
                                           &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("certificate");


    my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    $self->{ssl} = $ssl;

    DJabberd::Stanza::StartTLS->finalize_ssl_negotiation($self, $ssl, $ctx);

    return $self;
}

1;
