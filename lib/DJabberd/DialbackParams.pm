package DJabberd::DialbackParams;
use strict;
use Carp;
use Digest::HMAC_SHA1 qw(hmac_sha1_hex);

use DJabberd::Log;
our $logger = DJabberd::Log->get_logger();

sub new {
    my ($class, %opts) = @_;

    my $self = bless {}, $class;
    foreach my $f (qw(id recv orig vhost)) {
        $self->{$f} = delete $opts{$f} or croak "No '$f' field";
    }
    croak "Unknown params" if %opts;
    return $self;
}

sub concat_params {
    my $self = shift;
    return join("|", map { $self->{$_} } qw(id recv orig));
}

sub generate_dialback_result {
    my ($self, $cb) = @_;
    my $vhost = $self->{vhost};
    $logger->info("Generating dialback result for vhost $vhost->{server_name}");
    $vhost->get_secret_key(sub {
        my ($shandle, $secret) = @_;
        my $params = $self->concat_params;
        my $res = join("-", $shandle, hmac_sha1_hex($params, $secret));
        $logger->debug("Generated dialback result '$res' using secret(of handle '$shandle')='$secret', params='$params'");
        $cb->($res);
    });
}

sub verify_callback {
    my ($self, %args) = @_;
    my $vhost = $self->{vhost};

    my $restext    = delete $args{'result_text'};
    my $on_success = delete $args{'on_success'};
    my $on_failure = delete $args{'on_failure'};
    Carp::croak("args") if %args;

    my ($handle, $digest) = split(/-/, $restext);
    $logger->debug("verify callback, restext=[$restext], stream_id = $self->{id}");

    $vhost->get_secret_key_by_handle($handle, sub {
        my $secret = shift;
        $logger->debug("Secret(of handle '$handle') is '$secret'");

        # bogus handle if no secret
        unless ($secret) {
            $on_failure->();
            return;
        }

        my $params = $self->concat_params;
        $logger->debug("concat params = [$params]");
        my $proper_digest = hmac_sha1_hex($params, $secret);
        if ($digest eq $proper_digest) {
            $on_success->();
        } else {
            $on_failure->();
        }
    });
}

1;

