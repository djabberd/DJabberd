package DJabberd::Connection::OldSSLClientIn;
use strict;
use base 'DJabberd::Connection::ClientIn';

use Net::SSLeay;

sub new {
    my ($class, $sock, $vhost) = @_;
    my $self = $class->SUPER::new($sock, $vhost);

    my $ctx = Net::SSLeay::CTX_new()
        or die("Failed to create SSL_CTX $!");

    $Net::SSLeay::ssl_version = 10; # Insist on TLSv1

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
    $self->{ssl} = $ssl;
    $self->start_new_parser;

#    Net::SSLeay::set_verify($ssl, Net::SSLeay::VERIFY_PEER(), 0);

    my $fileno = $self->{sock}->fileno;
    warn "setting ssl ($ssl) fileno to $fileno\n";
    Net::SSLeay::set_fd($ssl, $fileno);

    $Net::SSLeay::trace = 2;

    #Net::SSLeay::connect($ssl) or Net::SSLeay::die_now("Failed SSL connect ($!)");

    my $err = Net::SSLeay::accept($ssl) and Net::SSLeay::die_if_ssl_error('ssl accept');
    warn "SSL accept err = $err\n";

    warn "$self:  Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n";

    $self->set_writer_func(sub {
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

    return $self;
}


1;