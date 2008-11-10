package DJabberd::Stanza::StartTLS;
use strict;
use base qw(DJabberd::Stanza);
use Net::SSLeay qw(ERROR_WANT_READ ERROR_WANT_WRITE ERROR_SYSCALL);

Net::SSLeay::load_error_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();
Net::SSLeay::randomize();

sub on_recv_from_server { &process }
sub on_recv_from_client { &process }

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
    Net::SSLeay::CTX_use_RSAPrivateKey_file ($ctx,  $conn->vhost->server->ssl_private_key_file,
                                             &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("private key");

    Net::SSLeay::CTX_use_certificate_file ($ctx, $conn->vhost->server->ssl_cert_file,
                                           &Net::SSLeay::FILETYPE_PEM);
    Net::SSLeay::die_if_ssl_error("certificate");


    my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");
    $conn->{ssl} = $ssl;
    $conn->restart_stream;
    
    DJabberd::Stanza::StartTLS->finalize_ssl_negotiation($conn, $ssl, $ctx);
}

# Complete the transformation of stream from tcp socket into ssl socket:
# 1. setup disconnect handler to free memory for $ssl and $ctx on connection close
# 2. SSL object is connected to underlying connection socket
# 3. 'accept' tells SSL to start negotiating encryption
# 4. set a socket write function that encrypts data before writting to the underlying socket
sub finalize_ssl_negotiation {
    my ($class, $conn, $ssl, $ctx) = @_;

    # Add a disconnect handler to this connection that will free memory
    # and remove references to junk no longer needed on close
    $conn->add_disconnect_handler(sub { 
         $conn->set_writer_func(sub { return 0 });
         Net::SSLeay::free($ssl);
         # Currently, a CTX_new is being called for every SSL connection.
         # It would be more efficient to create one $ctx per-vhost instead of per-connection
         # and to re-use that $ctx object for each new connection to that vhost.
         # This would eliminate the need to free $ctx here.
         Net::SSLeay::CTX_free($ctx);
         $conn->{ssl} = undef;
    });

    my $fileno = $conn->{sock}->fileno;
    warn "setting ssl ($ssl) fileno to $fileno\n";
    Net::SSLeay::set_fd($ssl, $fileno);

    $Net::SSLeay::trace = 2;

    my $rv = Net::SSLeay::accept($ssl);
    if (!$rv) {
        warn "SSL accept error on $conn\n";
        $conn->close;
        return;
    }

    warn "$conn:  Cipher `" . Net::SSLeay::get_cipher($ssl) . "'\n";

    $conn->set_writer_func(DJabberd::Stanza::StartTLS->danga_socket_writerfunc($conn));
}

sub actual_error_on_empty_read {
    my ($class, $ssl) = @_;
    my $err = Net::SSLeay::get_error($ssl, -1);
    if ($err == ERROR_WANT_READ || $err == ERROR_WANT_WRITE) {
        # Not an actual error, SSL is busy doing something like renegotiating encryption
        # just try again next time
        return undef;
    }
    if ($err == ERROR_SYSCALL) {
        # return the specific syscall error
        return "syscall error: $!"; 
    }
    # This is actually an error (return the SSL err code)
    # unlike the 'no-op' WANT_READ and WANT_WRITE
    return "ssl error $err: " . Net::SSLeay::ERR_error_string($err);
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

            if ($err == ERROR_WANT_READ) {
                $conn->write_when_readable;
                return 0;
            }
            if ($err == ERROR_WANT_WRITE) {
                # unclear here.  it just wants to write some more?  okay.
                # easy enough.  do nothing?
                return 0;
            }

            my $errstr = Net::SSLeay::ERR_error_string($err);
            warn " SSL write err = $err, $errstr\n";
            Net::SSLeay::print_errs("SSL_write");
            $conn->close;
            return 0;
        }

        return $written;
    };
}

1;

#  LocalWords:  conn
