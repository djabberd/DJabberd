package DJabberd::Stanza::DialbackResult;
use strict;
use base qw(DJabberd::Stanza);

use DJabberd::DNS;
use DJabberd::Connection::DialbackVerify;

sub process {
    my ($self, $conn) = @_;


    my $recv_server = $self->recv_server;
    my $orig_server = $self->orig_server;


    $conn->log->debug("Got a dailback result, oring: $orig_server, recv: $recv_server");

    unless ($conn->server->name eq $recv_server) {
        # TODO: make this a hook, whether a name is recognized.

        # If the value of the 'to' address does not match a hostname
        # recognized by the Receiving Server, then the Receiving
        # Server MUST generate a <host-unknown/> stream error
        # condition and terminate both the XML stream and the
        # underlying TCP connection.
        $conn->stream_error("host-unknown");
        return;
    }

    my $final_cb = DJabberd::Callback->new(
                                           pass => sub {
                                               $conn->dialback_result_valid(orig_server => $orig_server,
                                                                            recv_server => $recv_server);
                                           },
                                           fail => sub {
                                               my ($self_cb, $reason) = @_;
                                               $conn->dialback_result_invalid($reason);;
                                           },
                                           );
    # async DNS lookup
    DJabberd::DNS->srv(service  => "_xmpp-server._tcp",
                       domain   => $orig_server,
                       callback => sub {
                           my @ips = @_;
                           unless (@ips) {
                               # FIXME: send something better
                               die "No resolved IP";
                           }

                           my $ip = shift @ips;
                           DJabberd::Connection::DialbackVerify->new($ip, $conn, $self, $final_cb);
                       });
}

# always acceptable
sub acceptable_from_server { 1 }

sub dialback_to {
    my $self = shift;
    return $self->attr("{jabber:server:dialback}to");
}
*recv_server = \&dialback_to;

sub dialback_from {
    my $self = shift;
    return $self->attr("{jabber:server:dialback}from");
}
*orig_server = \&dialback_from;

sub result_text {
    my $self = shift;
    return $self->first_child;
}

1;
