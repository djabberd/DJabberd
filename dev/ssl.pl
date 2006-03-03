#!/usr/bin/perl

use strict;
use Socket;
use IO::Socket::INET;
use Net::SSLeay qw(die_now die_if_ssl_error);
use Net::SSLeay::Handle;

Net::SSLeay::load_error_strings();
Net::SSLeay::SSLeay_add_ssl_algorithms();   # Important!
Net::SSLeay::randomize();


my $dest_ip = gethostbyname ("mail.fitzpat.com");
my $dest_serv_params  = sockaddr_in(443, $dest_ip);

socket  (S, &AF_INET, &SOCK_STREAM, 0)  or die "socket: $!";
connect (S, $dest_serv_params)          or die "connect: $!";
select  (S); $| = 1; select (STDOUT);   # Eliminate STDIO buffering

my $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");

Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL)
    and die_if_ssl_error("ssl ctx set options");

my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");

my $err = Net::SSLeay::set_verify ($ssl,
                                &Net::SSLeay::VERIFY_CLIENT_ONCE,
                                sub {
                                    print "VERIFY CALLBACK = [@_]\n";
                                });
print "error = $err\n";

#my $sock = IO::Socket::INET->new(PeerAddr => "mail.fitzpat.com:443");

my $sock = \*S;

print "word.\n";
tie(*S2, "Net::SSLeay::Handle", $sock);
my $sock2 = \*S2;

print "word2.\n";

print $sock2 "GET / HTTP/1.0\r\nHost: mail.fitzpat.com\r\n\r\n";
while (<$sock2>) {
    print "GOT: $_";
}
print "Done.\n";

__END__

print "sock = $sock\n";
my $glob = *$sock{IO};
print "glob = $glob\n";

Net::SSLeay::set_fd($ssl, $sock->fileno);

Net::SSLeay::connect($ssl) or die_now("Failed SSL connect ($!)");
Net::SSLeay::write($ssl, "GET / HTTP/1.0\r\nHost: mail.fitzpat.com\r\n\r\n") or die_if_ssl_error("SSL write ($!)");
