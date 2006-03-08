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

    my $final_cb = DJabberd::Callback->new(
                                           pass => sub {
                                               $conn->dialback_verify_valid(from => $from, to => $to);
                                           },
                                           fail => sub {
                                               my ($self_cb, $reason) = @_;
                                               $conn->dialback_verify_invalid($reason);;
                                           },
                                           );
    # async DNS lookup
    DJabberd::DNS->new(
                       hostname => $from,
                       callback => sub {
                           my $ip = shift;
                           unless ($ip) {
                               # FIXME: send something better
                               die "No resolved IP";
                           }

                           DJabberd::Connection::DialbackVerify->new($ip, $conn, $self, $final_cb);
                       });
}


sub dialback_to {
    my $self = shift;
    return $self->attr("{jabber:server:dialback}to");
}

sub dialback_from {
    my $self = shift;
    return $self->attr("{jabber:server:dialback}from");
}

sub result_text {
    my $self = shift;
    return $self->first_child;
}

1;
