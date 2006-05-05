# this isn't meant to be used in production, but just for weird
# internal uses.  maybe you'll use it in production anyway.

package DJabberd::Connection::SimpleIn;
use strict;
use base 'DJabberd::Connection';
use fields (
            'read_buf',
            );

sub new {
    my ($class, $sock, $server) = @_;
    my $self = $class->SUPER::new($sock, $server);

    # set this later
    $self->{vhost}   = undef;
    $self->{read_buf} = '';

    warn "CONNECTION from " . $self->peer_ip_string . " == $self\n";

    return $self;
}

sub event_write {
    my $self = shift;
    $self->watch_write(0) if $self->write(undef);
}

# DJabberd::Connection::SimpleIn
sub event_read {
    my DJabberd::Connection::SimpleIn $self = shift;

    my $bref = $self->read(1024);
    return $self->close unless defined $bref;
    $self->{read_buf} .= $$bref;

    if ($self->{read_buf} =~ s/^(.*)\r?\n//) {
        my $line = $1;
        $self->process_line( $line );
    }
}

sub process_line {
    my DJabberd::Connection::SimpleIn $self = shift;
    my $line = shift;
    return $self->close unless $line =~ /^(\w+)\s*([^\n\r]*)/;
    my ($cmd, $rest) = ($1, $2);

    if ($cmd eq "set_vhost") {
        my $vhostname = $rest;
        my $vhost = $self->server->lookup_vhost($vhostname);
        unless ($vhost) {
            $self->write("ERROR no vhost '$vhostname'\n");
            return;
        }
        $self->{vhost} = $vhost;
        Scalar::Util::weaken($self->{vhost});
        $self->write("OK\n");
        return;
    }

    if ($cmd eq "send_xml") {
        my ($to, $enc_xml) = split(/\s+/, $rest);
        my $xml = durl($enc_xml);
        warn "SIMPLE: sending to '$to', the XML '$xml'\n";

        my $vhost = $self->vhost;
        unless ($vhost) {
            $self->write("ERROR must first 'set_vhost'\n");
            return;
        }

        my $dconn = $vhost->find_jid($to);
        unless ($dconn) {
            warn "error.\n";
            $self->write("ERROR\n");
            return;
        }

        warn "all good. dconn = $dconn\n";
        $dconn->write($xml);
        $self->write("OK\n");
        return;
    }

    $self->write("ERROR UNKNOWN_COMMAND\n");
}

# DJabberd::Connection::SimpleIn
sub event_err { my $self = shift; $self->close; }
sub event_hup { my $self = shift; $self->close; }

sub durl {
    my ($a) = @_;
    $a =~ tr/+/ /;
    $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    return $a;
}




1;
