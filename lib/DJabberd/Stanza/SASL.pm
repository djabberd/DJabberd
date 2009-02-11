package DJabberd::Stanza::SASL;
use strict;
use warnings;
use base qw(DJabberd::Stanza);

sub on_recv_from_server { die "unimplemented" }

use MIME::Base64 qw/encode_base64 decode_base64/;

## TODO:
## support 7.3.4, 7.4.1 <abort xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>
## change order of parameters? $challenge => $conn, instead of $conn => $challenge
## check number of auth failures, force deconnection, bad for t time 7.3.5 policy-violation


sub on_recv_from_client {
    my ($self, $conn) = @_;

    my $vhost = $conn->vhost
        # XXX
        or die "Send a proper error here"; # For now it must exists
    my $sasl = $vhost->sasl
        # XXX
        or die "Send a proper error here";

    return $self->handle_response($conn)
        if $self->element_name eq 'response';

    ## XXX should use a hash stored in vh directly
    my $mechanism = $self->attr("{}mechanism");

    #XXX proper error
    die "Not supported mechanism $mechanism"
        unless $vhost->{sasl_mechanisms} =~ /$mechanism/;

    $sasl->mechanism($mechanism);
    my $sasl_conn = $sasl->server_new("xmpp", $vhost->server_name);
    $conn->{sasl} = $sasl_conn;

    my $init = $self->first_child;
    if (!$init or $init eq '=') {
        $init = ''
    }
    else {
        $init = $self->decode($init);
    }

    my $challenge = $sasl_conn->server_start($init);
    if (my $error = $sasl_conn->error) {
        $self->send_failure($conn => $error);
    }
    else {
        if ($sasl_conn->need_step) {
            $self->send_challenge($conn => $challenge);
        }
        else {
            if ($sasl_conn->is_success) {
                ## early success (like for PLAIN mechanism)
                $self->ack_success($conn);
            }
        }
    }
    return;
}

sub send_challenge {
    my $self = shift;
    my ($conn, $challenge) = @_;

    $conn->log->info("Sending Challenge: $challenge");
    my $enc_challenge = $self->encode($challenge);
    my $xml = "<challenge xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>$enc_challenge</challenge>";
    $conn->xmllog->info($xml);
    $conn->write(\$xml);
}

## XXX not complete
sub send_failure {
    my $self = shift;
    my ($conn, $error) = @_;
    $conn->log->info("Sending error: $error");
    my $xml = <<EOF;
<failure xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><temporary-auth-failure/></failure>
EOF
    $conn->xmllog->info($xml);
    $conn->write(\$xml);
    return;
}

sub ack_success {
    my $self = shift;
    my ($conn, $challenge) = @_;

    # I can't say I know what I'm doing XXX
    my $sasl     = $conn->{sasl};
    my $username = $sasl->answer('username') || $sasl->answer('user');
    my $sname    = $conn->vhost->name;
    $conn->{sasl_authenticated_jid} = "$username\@$sname";

    my $xml;
    if (defined $challenge) {
        my $enc = $challenge ? $self->encode($challenge) : "=";
        $xml = "<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>$enc</success>";
    }
    else {
        $xml = "<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>";
    }
    $conn->xmllog->info($xml);
    $conn->write(\$xml);
    $conn->restart_stream;
}

sub handle_response {
    my $self = shift;
    my ($conn) = @_;

    my $sasl = $conn->{sasl};
    if (my $error = $sasl->error) {
        $self->send_failure($conn => $error);
        return;
    }
    if (! $sasl->need_step) {
        die "Weird this shouldn't happen ? XXX " . $sasl->is_success;
    }

    my $response = $self->first_child;
    $response = $self->decode($response);
    $conn->log->info("Got the response $response");

    my $challenge = $sasl->server_step($response);

    ## XXX refactor... this is duplicated with one step auth
    if (my $error = $sasl->error) {
        $self->send_failure($conn, $error);
    }
    elsif ($sasl->is_success) {
        $self->ack_success($conn, $challenge);
    }
    else {
        $self->send_challenge($conn, $challenge);
    }
    return;
}

sub encode {
    my $self = shift;
    my $str  = shift;
    return encode_base64($str, '');
}

sub decode {
    my $self = shift;
    my $str  = shift;
    return decode_base64($str);
}

1;
