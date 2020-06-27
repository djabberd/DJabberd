package DJabberd::Stanza::SASL;
use strict;
use warnings;
use base qw(DJabberd::Stanza);

use MIME::Base64 qw/encode_base64 decode_base64/;

sub acceptable_from_server { 1 }

sub on_recv_from_server {
    my $self = shift;
    my $conn = shift;

    $conn->log->debug("Got Server SASL Auth for conn ".$conn->{id}." with ".$self->as_xml);

    return $self->handle_exauth($conn)
        if $self->element_name eq 'auth'
	&& $self->attr('{}mechanism') eq 'EXTERNAL';

    return $self->send_failure("not-authorized" => $conn);
}

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

    return $self->handle_exauth(@_)
        if $self->element_name eq 'auth'
	&& $self->attr('{}mechanism') eq 'EXTERNAL';

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

    $sasl->server_step(
        $response => sub { $self->send_reply($conn->{sasl}, shift() => $conn) },
    );
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
    $opts->{tlsbindings} = $conn->{bindings};
    $saslmgr->mechanism($mechanism);
    my $sasl_conn = $saslmgr->server_new("xmpp", $vhost->server_name, $opts);
    $conn->{sasl} = $sasl_conn;

    my $init = $self->first_child;
    if (!$init or $init eq '=') {
        $init = '';
    }
    else {
        $init = $self->decode($init);
    }

    $sasl_conn->server_start(
        $init => sub { $self->send_reply($conn->{sasl}, shift() => $conn) },
    );
}

sub handle_exauth {
    my ($self, $conn) = @_;
    $conn->log->debug("Handling EXTERNAL: SASL Auth for conn ".$conn->{id});
    if($conn->ssl && $conn->sasl && $conn->sasl->isa('DJabberd::SASL::Connection::External')) {
        my $id = join('',grep{/\S+/}$self->children);
        $conn->log->debug("Found valid x509 certificate, validating auth request $id");
        # Well, do the auth now
        if($conn->is_server) {
            my $peer = '';
            # Identity should be explicitly specified or be stream "from" attribute
            my $host = (!$id || $id eq '=')? $conn->{from} : decode_base64($id);
            my $ret = $conn->sasl->srv_auth($host);
            $conn->log->debug("Authenticating server $host by $ret");
            if($ret == 1) {
                $conn->sasl->set_id($host);
                my $xml = "<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>";
                $conn->log_outgoing_data($xml);
                $conn->write(\$xml);
                $conn->log->info("Registering domain $host ($peer) on connection ".$conn->{id});
                $conn->peer_domain_set_verified($host);
                $conn->restart_stream;
            } elsif($ret < 0) {
                $self->send_failure('malformed-request' => $conn);
            } else {
                $self->send_failure('not-authorized' => $conn);
            }
        } else {
            my $jid;
            if(!$id || $id eq '=') {
                unless($jid = $self->sasl->usr_guess($conn->vhost)) {
                    $conn->log->debug("Cannot guess ID from certificate, no apropriate SAN found");
                    $self->send_failure('not-authorized' => $conn) unless($jid);
                }
            } else {
                # Validate requested identity
                $id = decode_base64($id);
                my $ret = $conn->sasl->usr_auth($id,$conn->vhost);
                if($ret == 1) {
                   $jid = $id;
                   $conn->log->info("Authenticating jid $jid on connection ".$conn->{id});
                } elsif($ret < 0) {
                   $self->send_failure('malformed-request' => $conn);
                } else {
                    $self->send_failure('not-authorized' => $conn);
                }
            }
            if($jid) {
                $conn->sasl->set_id($jid);
                $conn->sasl->set_authenticated_jid($jid);
                my $xml = "<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>";
                $conn->log_outgoing_data($xml);
                $conn->write(\$xml);
                $conn->restart_stream;
            }
        }
    } else {
        $self->send_failure("invalid-mechanism" => $conn);
    }
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
	$conn->log->debug("SASL Error: $error, $challenge");
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
