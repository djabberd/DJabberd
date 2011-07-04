
package DJabberd::Socket;

use strict;
use bytes;
use POSIX ();
use Time::HiRes ();
use AnyEvent;

use warnings;
no  warnings qw(deprecated);

use Sys::Syscall qw(:epoll);

use fields ('sock',              # underlying socket
            'fd',                # numeric file descriptor
            'write_buf',         # arrayref of scalars, scalarrefs, or coderefs to write
            'write_buf_offset',  # offset into first array of write_buf to start writing at
            'write_buf_size',    # total length of data in all write_buf items
            'write_set_watch',   # bool: true if we internally set watch_write rather than by a subclass
            'closed',            # bool: socket is closed
            'corked',            # bool: socket is corked
            'event_watch',       # bitmask of events the client is interested in (POLLIN,OUT,etc.)
            'peer_v6',           # bool: cached; if peer is an IPv6 address
            'peer_ip',           # cached stringified IP address of $sock
            'peer_port',         # cached port number of $sock
            'local_ip',          # cached stringified IP address of local end of $sock
            'local_port',        # cached port number of local end of $sock
            'writer_func',       # subref which does writing.  must return bytes written (or undef) and set $! on errors
            );

use Errno  qw(EINPROGRESS EWOULDBLOCK EISCONN ENOTSOCK
              EPIPE EAGAIN EBADF ECONNRESET ENOPROTOOPT);
use Socket qw(IPPROTO_TCP);
use Carp   qw(croak confess);

use constant TCP_CORK => ($^O eq "linux" ? 3 : 0); # FIXME: not hard-coded (Linux-specific too)
use constant DebugLevel => 0;

use constant POLLIN        => 1;
use constant POLLOUT       => 4;
use constant POLLERR       => 8;
use constant POLLHUP       => 16;
use constant POLLNVAL      => 32;

our (
     %Timers,                    # timers
     %FdWatchers,                # fd (num) -> [ AnyEvent read watcher, AnyEvent write watcher ]
     %DescriptorMap,             # fd (num) -> DJabberd::Socket object that owns it
     $DoProfile,                 # if on, enable profiling
     %Profiling,                 # what => [ utime, stime, calls ]
     $DoneInit,                  # if we've done the one-time module init yet
     %ToCloseIdleWatchers,       # fd (num) -> watcher .. set of active idle watchers to close fds

     );

Reset();

sub Reset {
    %Timers = ();
    %FdWatchers = ();
    %DescriptorMap = ();
}

sub AddTimer {
    my $class = shift;
    my ($secs, $coderef) = @_;

    my $timer = [ undef ];

    my $key = "$timer"; # Just stringify the timer array to get our hash key

    my $cancel = sub {
        delete $Timers{$key};
    };

    my $cb = sub {
        $coderef->();
        $cancel->();
    };

    $timer->[0] = $cancel;

    # We save the watcher in $Timers to keep it alive until it runs,
    # or until $cancel above overwrites it with undef to cause it to
    # get collected.
    $Timers{$key} = AnyEvent->timer(
        after => $secs,
        cb => $cb,
    );

    return bless $timer, 'DJabberd::Socket::Timer';
}

sub DescriptorMap {
    return wantarray ? %DescriptorMap : \%DescriptorMap;
}
*descriptor_map = *DescriptorMap;
*get_sock_ref = *DescriptorMap;

### Instance/Class Methods

sub new {
    my DJabberd::Socket $self = shift;
    $self = fields::new($self) unless ref $self;

    my $sock = shift;

    $self->{sock}        = $sock;
    my $fd = fileno($sock);

    Carp::cluck("undef sock and/or fd in DJabberd::Socket->new.  sock=" . ($sock || "") . ", fd=" . ($fd || ""))
        unless $sock && $fd;

    $self->{fd}          = $fd;
    $self->{write_buf}      = [];
    $self->{write_buf_offset} = 0;
    $self->{write_buf_size} = 0;
    $self->{closed} = 0;
    $self->{corked} = 0;

    $self->{event_watch} = POLLERR|POLLHUP|POLLNVAL;

    # Create the slots where the watchers will go if the caller
    # decides to watch_read or watch_write.
    $FdWatchers{$fd} = [ undef, undef ];

    Carp::cluck("DJabberd::Socket::new blowing away existing descriptor map for fd=$fd ($DescriptorMap{$fd})")
        if $DescriptorMap{$fd};

    $DescriptorMap{$fd} = $self;
    return $self;
}


sub tcp_cork {
    my DJabberd::Socket $self = $_[0];
    my $val = $_[1];

    # make sure we have a socket
    return unless $self->{sock};
    return if $val == $self->{corked};

    my $rv;
    if (TCP_CORK) {
        $rv = setsockopt($self->{sock}, IPPROTO_TCP, TCP_CORK,
                         pack("l", $val ? 1 : 0));
    } else {
        # FIXME: implement freebsd *PUSH sockopts
        $rv = 1;
    }

    # if we failed, close (if we're not already) and warn about the error
    if ($rv) {
        $self->{corked} = $val;
    } else {
        if ($! == EBADF || $! == ENOTSOCK) {
            # internal state is probably corrupted; warn and then close if
            # we're not closed already
            warn "setsockopt: $!";
            $self->close('tcp_cork_failed');
        } elsif ($! == ENOPROTOOPT || $!{ENOTSOCK} || $!{EOPNOTSUPP}) {
            # TCP implementation doesn't support corking, so just ignore it
            # or we're trying to tcp-cork a non-socket (like a socketpair pipe
            # which is acting like a socket, which Perlbal does for child
            # processes acting like inetd-like web servers)
        } else {
            # some other error; we should never hit here, but if we do, die
            die "setsockopt: $!";
        }
    }
}

sub steal_socket {
    my DJabberd::Socket $self = $_[0];
    return if $self->{closed};

    # cleanup does most of the work of closing this socket
    $self->_cleanup();

    # now undef our internal sock and fd structures so we don't use them
    my $sock = $self->{sock};
    $self->{sock} = undef;
    return $sock;
}

sub close {
    my DJabberd::Socket $self = $_[0];
    return if $self->{closed};

    # print out debugging info for this close
    if (DebugLevel) {
        my ($pkg, $filename, $line) = caller;
        my $reason = $_[1] || "";
        warn "Closing \#$self->{fd} due to $pkg/$filename/$line ($reason)\n";
    }

    # this does most of the work of closing us
    $self->_cleanup();

    # defer closing the actual socket until the event loop is done
    # processing this round of events.  (otherwise we might reuse fds)
    if ($self->{sock}) {
        my $fd = fileno($self->{sock});
        my $sock = $self->{sock};
        $ToCloseIdleWatchers{$fd} = AnyEvent->idle(cb => sub {
            $sock->close();
            delete $DescriptorMap{$fd};
            # Disable this watcher
            delete $ToCloseIdleWatchers{$fd};
        });
    }

    return 0;
}

### METHOD: _cleanup()
### Called by our closers so we can clean internal data structures.
sub _cleanup {
    my DJabberd::Socket $self = $_[0];

    # we're effectively closed; we have no fd and sock when we leave here
    $self->{closed} = 1;

    # we need to flush our write buffer, as there may
    # be self-referential closures (sub { $client->close })
    # preventing the object from being destroyed
    $self->{write_buf} = [];

    # uncork so any final data gets sent.  only matters if the person closing
    # us forgot to do it, but we do it to be safe.
    $self->tcp_cork(0);

    # now delete from mappings.  this fd no longer belongs to us, so we don't want
    # to get alerts for it if it becomes writable/readable/etc.
    delete $FdWatchers{$self->{fd}};

    # we explicitly don't delete from DescriptorMap here until we
    # actually close the socket, as we might be in the middle of
    # processing an epoll_wait/etc that returned hundreds of fds, one
    # of which is not yet processed and is what we're closing.  if we
    # keep it in DescriptorMap, then the event harnesses can just
    # looked at $pob->{closed} and ignore it.  but if it's an
    # un-accounted for fd, then it (understandably) freak out a bit
    # and emit warnings, thinking their state got off.

    # and finally get rid of our fd so we can't use it anywhere else
    $self->{fd} = undef;
}

sub sock {
    my DJabberd::Socket $self = shift;
    return $self->{sock};
}

sub set_writer_func {
   my DJabberd::Socket $self = shift;
   my $wtr = shift;
   Carp::croak("Not a subref") unless !defined $wtr || UNIVERSAL::isa($wtr, "CODE");
   $self->{writer_func} = $wtr;
}

sub write {
    my DJabberd::Socket $self;
    my $data;
    ($self, $data) = @_;

    # nobody should be writing to closed sockets, but caller code can
    # do two writes within an event, have the first fail and
    # disconnect the other side (whose destructor then closes the
    # calling object, but it's still in a method), and then the
    # now-dead object does its second write.  that is this case.  we
    # just lie and say it worked.  it'll be dead soon and won't be
    # hurt by this lie.
    return 1 if $self->{closed};

    my $bref;

    # just queue data if there's already a wait
    my $need_queue;

    if (defined $data) {
        $bref = ref $data ? $data : \$data;
        if ($self->{write_buf_size}) {
            push @{$self->{write_buf}}, $bref;
            $self->{write_buf_size} += ref $bref eq "SCALAR" ? length($$bref) : 1;
            return 0;
        }

        # this flag says we're bypassing the queue system, knowing we're the
        # only outstanding write, and hoping we don't ever need to use it.
        # if so later, though, we'll need to queue
        $need_queue = 1;
    }

  WRITE:
    while (1) {
        return 1 unless $bref ||= $self->{write_buf}[0];

        my $len;
        eval {
            $len = length($$bref); # this will die if $bref is a code ref, caught below
        };
        if ($@) {
            if (UNIVERSAL::isa($bref, "CODE")) {
                unless ($need_queue) {
                    $self->{write_buf_size}--; # code refs are worth 1
                    shift @{$self->{write_buf}};
                }
                $bref->();

                # code refs are just run and never get reenqueued
                # (they're one-shot), so turn off the flag indicating the
                # outstanding data needs queueing.
                $need_queue = 0;

                undef $bref;
                next WRITE;
            }
            die "Write error: $@ <$bref>";
        }

        my $to_write = $len - $self->{write_buf_offset};
        my $written;
        if (my $wtr = $self->{writer_func}) {
            $written = $wtr->($bref, $to_write, $self->{write_buf_offset});
        } else {
            $written = syswrite($self->{sock}, $$bref, $to_write, $self->{write_buf_offset});
        }

        if (! defined $written) {
            if ($! == EPIPE) {
                return $self->close("EPIPE");
            } elsif ($! == EAGAIN) {
                # since connection has stuff to write, it should now be
                # interested in pending writes:
                if ($need_queue) {
                    push @{$self->{write_buf}}, $bref;
                    $self->{write_buf_size} += $len;
                }
                $self->{write_set_watch} = 1 unless $self->{event_watch} & POLLOUT;
                $self->watch_write(1);
                return 0;
            } elsif ($! == ECONNRESET) {
                return $self->close("ECONNRESET");
            }

            DebugLevel >= 1 && $self->debugmsg("Closing connection ($self) due to write error: $!\n");

            return $self->close("write_error");
        } elsif ($written != $to_write) {
            DebugLevel >= 2 && $self->debugmsg("Wrote PARTIAL %d bytes to %d",
                                               $written, $self->{fd});
            if ($need_queue) {
                push @{$self->{write_buf}}, $bref;
                $self->{write_buf_size} += $len;
            }
            # since connection has stuff to write, it should now be
            # interested in pending writes:
            $self->{write_buf_offset} += $written;
            $self->{write_buf_size} -= $written;
            $self->on_incomplete_write;
            return 0;
        } elsif ($written == $to_write) {
            DebugLevel >= 2 && $self->debugmsg("Wrote ALL %d bytes to %d (nq=%d)",
                                               $written, $self->{fd}, $need_queue);
            $self->{write_buf_offset} = 0;

            if ($self->{write_set_watch}) {
                $self->watch_write(0);
                $self->{write_set_watch} = 0;
            }

            # this was our only write, so we can return immediately
            # since we avoided incrementing the buffer size or
            # putting it in the buffer.  we also know there
            # can't be anything else to write.
            return 1 if $need_queue;

            $self->{write_buf_size} -= $written;
            shift @{$self->{write_buf}};
            undef $bref;
            next WRITE;
        }
    }
}

sub on_incomplete_write {
    my DJabberd::Socket $self = shift;
    $self->{write_set_watch} = 1 unless $self->{event_watch} & POLLOUT;
    $self->watch_write(1);
}

sub read {
    my DJabberd::Socket $self = shift;
    return if $self->{closed};
    my $bytes = shift;
    my $buf;
    my $sock = $self->{sock};

    # if this is too high, perl quits(!!).  reports on mailing lists
    # don't seem to point to a universal answer.  5MB worked for some,
    # crashed for others.  1MB works for more people.  let's go with 1MB
    # for now.  :/
    my $req_bytes = $bytes > 1048576 ? 1048576 : $bytes;

    my $res = sysread($sock, $buf, $req_bytes, 0);
    DebugLevel >= 2 && $self->debugmsg("sysread = %d; \$! = %d", $res, $!);

    if (! $res && $! != EWOULDBLOCK) {
        # catches 0=conn closed or undef=error
        DebugLevel >= 2 && $self->debugmsg("Fd \#%d read hit the end of the road.", $self->{fd});
        return undef;
    }

    return \$buf;
}

sub event_read  { die "Base class event_read called for $_[0]\n"; }
sub event_err   { die "Base class event_err called for $_[0]\n"; }
sub event_hup   { die "Base class event_hup called for $_[0]\n"; }
sub event_write {
    my $self = shift;
    $self->write(undef);
}

sub watch_read {
    my DJabberd::Socket $self = shift;
    return if $self->{closed} || !$self->{sock};

    my $val = shift;
    my $fd = fileno($self->{sock});
    my $watchers = $FdWatchers{$fd};
    if ($val) {
        $watchers->[0] = AnyEvent->io(
            fh => $fd,
            poll => 'r',
            cb => sub {
                $self->event_read() unless $self->{closed};
            },
        );
    }
    else {
        $watchers->[0] = undef;
    }
}

sub watch_write {
    my DJabberd::Socket $self = shift;
    return if $self->{closed} || !$self->{sock};

    my $val = shift;
    my $fd = fileno($self->{sock});

    if ($val && caller ne __PACKAGE__) {
        # A subclass registered interest, it's now responsible for this.
        $self->{write_set_watch} = 0;
    }

    my $watchers = $FdWatchers{$fd};
    if ($val) {
        $watchers->[1] = AnyEvent->io(
            fh => $fd,
            poll => 'w',
            cb => sub {
                $self->event_write() unless $self->{closed};
            },
        );
    }
    else {
        $watchers->[1] = undef;
    }
}

sub debugmsg {
    my ( $self, $fmt, @args ) = @_;
    confess "Not an object" unless ref $self;

    chomp $fmt;
    printf STDERR ">>> $fmt\n", @args;
}


sub peer_ip_string {
    my DJabberd::Socket $self = shift;
    return _undef("peer_ip_string undef: no sock") unless $self->{sock};
    return $self->{peer_ip} if defined $self->{peer_ip};

    my $pn = getpeername($self->{sock});
    return _undef("peer_ip_string undef: getpeername") unless $pn;

    my ($port, $iaddr) = eval {
        if (length($pn) >= 28) {
            return Socket6::unpack_sockaddr_in6($pn);
        } else {
            return Socket::sockaddr_in($pn);
        }
    };

    if ($@) {
        $self->{peer_port} = "[Unknown peerport '$@']";
        return "[Unknown peername '$@']";
    }

    $self->{peer_port} = $port;

    if (length($iaddr) == 4) {
        return $self->{peer_ip} = Socket::inet_ntoa($iaddr);
    } else {
        $self->{peer_v6} = 1;
        return $self->{peer_ip} = Socket6::inet_ntop(Socket6::AF_INET6(),
                                                     $iaddr);
    }
}

sub peer_addr_string {
    my DJabberd::Socket $self = shift;
    my $ip = $self->peer_ip_string
        or return undef;
    return $self->{peer_v6} ?
        "[$ip]:$self->{peer_port}" :
        "$ip:$self->{peer_port}";
}

sub local_ip_string {
    my DJabberd::Socket $self = shift;
    return _undef("local_ip_string undef: no sock") unless $self->{sock};
    return $self->{local_ip} if defined $self->{local_ip};

    my $pn = getsockname($self->{sock});
    return _undef("local_ip_string undef: getsockname") unless $pn;

    my ($port, $iaddr) = Socket::sockaddr_in($pn);
    $self->{local_port} = $port;

    return $self->{local_ip} = Socket::inet_ntoa($iaddr);
}

sub local_addr_string {
    my DJabberd::Socket $self = shift;
    my $ip = $self->local_ip_string;
    return $ip ? "$ip:$self->{local_port}" : undef;
}

sub as_string {
    my DJabberd::Socket $self = shift;
    my $rw = "(" . ($self->{event_watch} & POLLIN ? 'R' : '') .
                   ($self->{event_watch} & POLLOUT ? 'W' : '') . ")";
    my $ret = ref($self) . "$rw: " . ($self->{closed} ? "closed" : "open");
    my $peer = $self->peer_addr_string;
    if ($peer) {
        $ret .= " to " . $self->peer_addr_string;
    }
    return $ret;
}

sub _undef {
    return undef unless $ENV{DS_DEBUG};
    my $msg = shift || "";
    warn "DJabberd::Socket: $msg\n";
    return undef;
}

package DJabberd::Socket::Timer;
# [$cancel_coderef];
sub cancel {
    $_[0][0]->();
}

1;

