package DJabberd::Stanza::StartTLS;
use strict;
use base qw(DJabberd::Stanza);
use Net::SSLeay;

Net::SSLeay::load_error_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();
Net::SSLeay::randomize();

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

    $conn->set_writer_func(sub {
        my ($bref, $to_write, $offset) = @_;

        # we can't write a lot or we get some SSL non-blocking error
        $to_write = 4096 if $to_write > 4096;

        my $str = substr($$bref, $offset, $to_write);
        #warn "Writing over SSL (to_write=$to_write, off=$offset): $str\n";
        my $written = Net::SSLeay::write($ssl, $str);
        #warn "  returned = $written\n";
        if ($written == -1) {
            my $err = Net::SSLeay::get_error($ssl, $written);
            my $errstr = Net::SSLeay::ERR_error_string($err);
            warn " SSL write err = $err, $errstr\n";
            Net::SSLeay::print_errs("SSL_write");
            die "we died writing\n";
        }

        return $written;
    });

    #warn "socked pre-SSL is: $conn->{sock}\n";
    #my $rv = IO::Socket::SSL->start_SSL($conn->{sock}); #, { SSL_verify_mode => 0x00 });
    #my $fileno = fileno $conn->{sock};
    #warn "was fileno = $fileno\n";
    #my $sym = gensym();
    #my $ssl = IO::Socket::SSL->new_from_fd($fileno);
    #warn " got ssl = $ssl, error = $@ / $!\n";
    #warn " fileno = ", fileno($ssl), "\n";
    #  my $tied = tie($sym, "DJabberd::SSL");
    # warn "Started SSL with $conn->{sock}, tied = $tied\n";

}

1;

#  LocalWords:  conn
