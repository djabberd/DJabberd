package DJabberd::Stanza::DialbackResult;
use strict;
use base qw(DJabberd::Stanza);

use DJabberd::DNS;
use DJabberd::Connection::DialbackVerify;

sub process {
    my ($self, $conn) = @_;

    warn "GOT a dialback result: " . $self->as_xml;

    my $to   = $self->dialback_to;
    my $from = $self->dialback_from;

    warn " from: $from, to: $to\n";

    unless ($conn->server->name eq $to) {
        # FIXME: send correct error to client
        die "bogus 'to' address'";
    }

    # async DNS lookup
    DJabberd::DNS->new(
                       hostname => $from,
                       callback => sub {
                           my $ip = shift;
                           warn "callback called w/ ip= $ip\n";
                           $self->process_given_host_and_ip($from, $ip);
                       });
}

sub process_given_host_and_ip {
    my ($self, $fromname, $fromip) = @_;

    unless ($fromip) {
        # FIXME: send something better
        die "No resolved IP";
    }

    # TODO: decide if we trust fromip
    warn "dialback result from: $fromname [$fromip]\n";

    my $callback = DJabberd::Callback->new(error => sub {},
                                           good => sub {},
                                           bad => sub {});

    #DJabberd::Connection::DialbackVerify->new($sock, $callback);

}

sub dialback_to {
    my $self = shift;
    return $self->attr("{jabber:server:dialback}to");
}

sub dialback_from {
    my $self = shift;
    return $self->attr("{jabber:server:dialback}from");
}


1;
