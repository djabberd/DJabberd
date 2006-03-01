# stolen from POE::Component::XMPP and renamed for safety...

package DJabberd::SSL;

use strict;

use vars qw($VERSION);
$VERSION = (qw($Revision$ ))[1];

use POSIX qw(F_GETFL F_SETFL O_NONBLOCK EAGAIN EWOULDBLOCK);

use Net::SSLeay qw(ERROR_WANT_READ ERROR_WANT_WRITE);
use Net::SSLeay::Handle;
use vars qw(@ISA);
@ISA = qw(Net::SSLeay::Handle);

my %Filenum_Object;

sub _get_self {
  return $Filenum_Object{fileno(shift)};
}

sub _get_ssl {
  my $socket = shift;
  return $Filenum_Object{fileno($socket)}->{ssl};
}

sub _set_filenum_obj {
  my ($self, $fileno, $ssl, $ctx, $socket, $accepted) = @_;
  $Filenum_Object{$fileno} =
  { ssl    => $ssl,
    ctx    => $ctx,
    socket => $socket,
    fileno => $fileno,
    _is_accepted => $accepted,
  };
}

sub TIEHANDLE {
  my ($class, $socket, $port) = @_;

  # Net::SSLeay needs nonblocking for setup.
  my $flags = fcntl($socket, F_GETFL, 0) or die $!;
  until (fcntl($socket, F_SETFL, $flags | O_NONBLOCK)) {
    die $! unless $! == EAGAIN or $! == EWOULDBLOCK;
  }

  ref $socket eq "GLOB" or $socket = $class->make_socket($socket, $port);

  $class->_initialize();

  my $ctx = Net::SSLeay::CTX_new() or die_now("Failed to create SSL_CTX $!");
  my $ssl = Net::SSLeay::new($ctx) or die_now("Failed to create SSL $!");

  my $fileno = fileno($socket);

  Net::SSLeay::set_fd($ssl, $fileno);   # Must use fileno

  my $connected = 0;
  my $resp = Net::SSLeay::connect($ssl);
  if ($resp <= 0) { # 0 is really controlled shutdown but we signal error
    my $errno = Net::SSLeay::get_error($ssl, $resp);
    if ($errno == ERROR_WANT_READ or $errno == ERROR_WANT_WRITE) {
      # we try again next time in WRITE
    }
    else {
      # handshake failed
      warn "handshake failed: $errno";
      return undef;
    }
  }
  else {
    $connected = 1;
  }

  $Filenum_Object{$fileno} =
  { ssl    => $ssl,
    ctx    => $ctx,
    socket => $socket,
    fileno => $fileno,
    _is_connected => $connected,
  };

  return bless $socket, $class;
}

sub READ {
  my ($socket, $buf, $len, $offset) = \ (@_);
  my $ssl = $$socket->_get_ssl();
  my $self = $$socket->_get_self();

  if (exists $self->{_is_accepted} && $self->{_is_accepted} == 0) {
    my $resp = Net::SSLeay::accept($ssl);
    if ($resp <= 0) {
      if (Net::SSLeay::get_error($ssl, $resp) == ERROR_WANT_READ) {
        return $$len;
      }
      else {
        warn "handshake failed";
        return undef;
      }
    }
    $self->{_is_accepted} = 1;
    return $$len;
  }

  # No offset.  Replace the buffer.
  unless (defined $$offset) {
    $$buf = Net::SSLeay::read($ssl, $$len);
    return length($$buf) if defined $$buf;
    $$buf = "";
    return;
  }

  defined(my $read = Net::SSLeay::read($ssl, $$len))
    or return undef;

  my $buf_len = length($$buf);
  $$offset > $buf_len and $$buf .= chr(0) x ($$offset - $buf_len);
  substr($$buf, $$offset) = $read;
  return length($read);
}

sub WRITE {
  my $socket = shift;
  my ($buf, $len, $offset) = @_;
  $offset = 0 unless defined $offset;
  my $ssl  = $socket->_get_ssl();
  my $self = $socket->_get_self();

  if (exists $self->{_is_connected} && $self->{_is_connected} == 0) {
    my $resp = Net::SSLeay::connect($ssl);
    if ($resp <= 0) {
      my $errno = Net::SSLeay::get_error($ssl, $resp);
      if ($errno == ERROR_WANT_WRITE or $errno == ERROR_WANT_READ) {
        return 0;
      }
      else {
        warn "handshake failed: $errno";
        return undef;
      }
    }
    $self->{_is_connected} = 1;
  }

  # Return number of characters written.
  my $wrote_len = Net::SSLeay::write($ssl, substr($buf, $offset, $len));

  # Net::SSLeay::write() returns the number of bytes written, or -1 on
  # error.  Normal syswrite() expects 0 here.
  return 0 if $wrote_len < 0;
  return $wrote_len;
}

sub CLOSE {
  my $socket = shift;
  my $fileno = fileno($socket);
  my $self = $socket->_get_self();
  delete $Filenum_Object{$fileno};
  Net::SSLeay::free ($self->{ssl});
  Net::SSLeay::CTX_free ($self->{ctx});
  close $socket;
}

1;

__END__

=head1 NAME

POE::Component::Client::HTTP::SSL - non-blocking SSL file handles

=head1 SYNOPSIS

  See Net::SSLeay::Handle

=head1 DESCRIPTION

This is a temporary subclass of Net::SSLeay::Handle with what I
consider proper read() and sysread() semantics.  This module will go
away if or when Net::SSLeay::Handle adopts these semantics.

POE::Component::Client::HTTP::SSL functions identically to
Net::SSLeay::Handle, but the READ function does not block until LENGTH
bytes are read.

=head1 SEE ALSO

Net::SSLeay::Handle

=head1 BUGS

None known.

=head1 AUTHOR & COPYRIGHTS

POE::Component::Client::HTTP::SSL is Copyright 1999-2002 by Rocco
Caputo.  All rights are reserved.  This module is free software; you
may redistribute it and/or modify it under the same terms as Perl
itself.

Rocco may be contacted by e-mail via rcaputo@cpan.org.

=cut
