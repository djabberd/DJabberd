package DJabberd::Connection::OldSSLClientIn;
use strict;
use base 'DJabberd::Connection::ClientIn';
use DJabberd::Stanza::StartTLS;

use Net::SSLeay;

use constant SSL_MODE_ENABLE_PARTIAL_WRITE       => 1;
use constant SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER => 2;
use constant SSL_MODE_AUTO_RETRY                 => 4;

sub new {
    my ($class, $sock, $vhost) = @_;
    my $self = $class->SUPER::new($sock, $vhost);

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
    Net::SSLeay::CTX_use_RSAPrivateKey_file ($ctx, 'server-key.pem',
                                             &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("private key");

    Net::SSLeay::CTX_use_certificate_file ($ctx, 'server-cert.pem',
                                           &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("certificate");


    my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    $self->{ssl} = $ssl;

#    Net::SSLeay::set_verify($ssl, Net::SSLeay::VERIFY_PEER(), 0);

    my $fileno = $self->{sock}->fileno;
    warn "setting ssl ($ssl) fileno to $fileno\n";
    Net::SSLeay::set_fd($ssl, $fileno);

    $Net::SSLeay::trace = 2;

    #Net::SSLeay::connect($ssl) or Net::SSLeay::die_now("Failed SSL connect ($!)");

    my $rv = Net::SSLeay::accept($ssl);
    if (!$rv) {
        warn "SSL accept error on $self\n";
        $self->close;
        return;
    }

    warn "$self:  Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n";

    $self->set_writer_func(DJabberd::Stanza::StartTLS->danga_socket_writerfunc($self));
    return $self;
}

1;
