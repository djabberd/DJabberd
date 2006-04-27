package DJabberd::Stanza::StartTLS;
use strict;
use base qw(DJabberd::Stanza);
use Net::SSLeay;

Net::SSLeay::load_error_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();
Net::SSLeay::randomize();

use constant SSL_ERROR_WANT_READ     => 2;
use constant SSL_ERROR_WANT_WRITE    => 3;

sub can_do_ssl {
    return -e 'server-key.pem' && -e 'server-cert.pem';
}

sub process {
    my ($self, $conn) = @_;

    # {=tls-no-spaces} -- we can't send spaces after the closing bracket
    $conn->write("<proceed xmlns='urn:ietf:params:xml:ns:xmpp-tls' />");

    my $ctx = Net::SSLeay::CTX_new()
        or die("Failed to create SSL_CTX $!");

    $Net::SSLeay::ssl_version = 10; # Insist on TLSv1
    #$Net::SSLeay::ssl_version = 3; # Insist on SSLv3

    Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL)
        and Net::SSLeay::die_if_ssl_error("ssl ctx set options");

    Net::SSLeay::CTX_set_mode($ctx, 1)  # enable partial writes
        and Net::SSLeay::die_if_ssl_error("ssl ctx set options");

    # Following will ask password unless private key is not encrypted
    Net::SSLeay::CTX_use_RSAPrivateKey_file ($ctx, 'server-key.pem',
                                             &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("private key");

    Net::SSLeay::CTX_use_certificate_file ($ctx, 'server-cert.pem',
                                           &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("certificate");


    my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    $conn->{ssl} = $ssl;
    $conn->start_new_parser;

#    Net::SSLeay::set_verify($ssl, Net::SSLeay::VERIFY_PEER(), 0);

    my $fileno = $conn->{sock}->fileno;
    warn "setting ssl ($ssl) fileno to $fileno\n";
    Net::SSLeay::set_fd($ssl, $fileno);

    $Net::SSLeay::trace = 2;

    #Net::SSLeay::connect($ssl) or Net::SSLeay::die_now("Failed SSL connect ($!)");

    my $err = Net::SSLeay::accept($ssl) and Net::SSLeay::die_if_ssl_error('ssl accept');
    warn "SSL accept err = $err\n";

    warn "$conn:  Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n";

    $conn->set_writer_func(DJabberd::Stanza::StartTLS->danga_socket_writerfunc($conn));
}

sub danga_socket_writerfunc {
    my ($class, $conn) = @_;
    my $ssl = $conn->{ssl};
    return sub {
        my ($bref, $to_write, $offset) = @_;

        # unless our event_read has been called, we don't want to try
        # to do any work now.  and probably we should complain.
        if ($conn->{write_when_readable}) {
            warn "writer func called when we're waiting for readability first.\n";
            return 0;
        }

        # we can't write a lot or we get some SSL non-blocking error.
        # NO LONGER RELEVANT?
        # $to_write = 4096 if $to_write > 4096;

        my $str = substr($$bref, $offset, $to_write);
        my $written = Net::SSLeay::write($ssl, $str);

        if ($written == -1) {
            my $err = Net::SSLeay::get_error($ssl, $written);

            if ($err == SSL_ERROR_WANT_READ) {
                $conn->write_when_readable;
                return 0;
            }
            if ($err == SSL_ERROR_WANT_WRITE) {
                # unclear here.  it just wants to write some more?  okay.
                # easy enough.  do nothing?
                return 0;
            }

            my $errstr = Net::SSLeay::ERR_error_string($err);
            warn " SSL write err = $err, $errstr\n";
            Net::SSLeay::print_errs("SSL_write");
            die "we died writing\n";
        }

        return $written;
    };
}

1;

#  LocalWords:  conn
