package DJabberd::Stanza::SASL;
use strict;
use warnings;
use base qw(DJabberd::Stanza);

use MIME::Base64 qw/encode_base64 decode_base64/;

sub on_recv_from_server { die "unimplemented" }

## TODO:
## check number of auth failures, force deconnection, bad for t time §7.3.5 policy-violation
## Provide hooks for Authen:: modules to return details about errors:
## - credentials-expired
## - account-disabled
## - invalid-authzid
## - temporary-auth-failure
## these hooks should probably additions to parameters taken by GetPassword, CheckClearText
## right now all these errors results in not-authorized being returned

sub on_recv_from_client {
    my $self = shift;

    return $self->handle_abort(@_)
        if $self->element_name eq 'abort';

    return $self->handle_response(@_)
        if $self->element_name eq 'response';

    return $self->handle_auth(@_)
        if $self->element_name eq 'auth';
}

## supports §7.3.4, §7.4.1
## handles: <abort xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>
sub handle_abort {
    my ($self, $conn) = @_;

    $self->send_failure("aborted" => $conn);
    return;
}

sub handle_response {
    my $self = shift;
    my ($conn) = @_;

    my $sasl = $conn->sasl
        or return $self->send_failure("malformed-request" => $conn);

    if (my $error = $sasl->error) {
        return $self->send_failure("not-authorized" => $conn);
    }
    if (! $sasl->need_step) {
        $conn->log->info("sasl negotiation unexpected end");
        return $self->send_failure("malformed-request" => $conn);
    }

    my $response = $self->first_child;
    $response = $self->decode($response);
    $conn->log->info("Got the response $response");

    my $challenge = $sasl->server_step($response);
    return $self->send_reply($sasl, $challenge => $conn);
}

sub handle_auth {
    my ($self, $conn) = @_;

    my $fallback = sub {
        $self->send_failure("invalid-mechanism" => $conn);
    };

    my $vhost = $conn->vhost
        or die "There is no vhost";

    my $saslmgr;
    $vhost->run_hook_chain( phase => "GetSASLManager",
                            args  => [ conn => $conn ],
                            methods => {
                                get => sub {
                                     (undef, $saslmgr) = @_;
                                },
                            },
                            fallback => $fallback,
    );
    die "no SASL" unless $saslmgr; 

    ## TODO: §7.4.4.  encryption-required
    my $mechanism = $self->attr("{}mechanism");
    return $self->send_failure("invalid-mechanism" => $conn)
        unless $saslmgr->is_mechanism_supported($mechanism);

    ## we don't support it for now
    my $opts = { no_integrity => 1 };
    $saslmgr->mechanism($mechanism);
    my $sasl_conn = $saslmgr->server_new("xmpp", $vhost->server_name, $opts);
    $conn->{sasl} = $sasl_conn;

    my $init = $self->first_child;
    if (!$init or $init eq '=') {
        $init = ''
    }
    else {
        $init = $self->decode($init);
    }

    my $challenge = $sasl_conn->server_start($init);
    return $self->send_reply($sasl_conn, $challenge => $conn);
}

sub send_challenge {
    my $self = shift;
    my ($challenge, $conn) = @_;

    $conn->log->debug("Sending Challenge: $challenge");
    my $enc_challenge = $self->encode($challenge);
    my $xml = "<challenge xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>$enc_challenge</challenge>";
    $conn->xmllog->info($xml);
    $conn->write(\$xml);
}

sub send_failure {
    my $self = shift;
    my ($error, $conn) = @_;
    $conn->log->debug("Sending error: $error");
    my $xml = <<EOF;
<failure xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><$error/></failure>
EOF
    $conn->xmllog->info($xml);
    $conn->write(\$xml);
    return;
}

sub ack_success {
    my $self = shift;
    my ($sasl_conn, $challenge, $conn) = @_;

    my $username = $sasl_conn->answer('username') || $sasl_conn->answer('user');
    my $sname = $conn->vhost->name;
    unless ($username && $sname) {
        $conn->log->error("Couldn't bind to a jid, declining.");
        $self->send_failure("not-authorized" => $conn);
        return;
    }
    my $authenticated_jid = "$username\@$sname";
    $sasl_conn->set_authenticated_jid($authenticated_jid);

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
    if (($sasl_conn->property('ssf') || 0) > 0) {
        $conn->log->info("SASL: Securing socket");
        $conn->log->warn("This will probably NOT work");
        $sasl_conn->securesocket($conn);
    }
    else {
        $conn->log->info("SASL: Not securing socket");
    }
    $conn->restart_stream;
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

sub send_reply {
    my $self = shift;
    my ($sasl_conn, $challenge, $conn) = @_;

    if (my $error = $sasl_conn->error) {
        $self->send_failure("not-authorized" => $conn);
    }
    elsif ($sasl_conn->is_success) {
        $self->ack_success($sasl_conn, $challenge => $conn);
    }
    else {
        $self->send_challenge($challenge => $conn);
    }
    return;
}

1;
