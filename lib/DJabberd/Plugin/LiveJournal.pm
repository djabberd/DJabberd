package DJabberd::Plugin::LiveJournal;
use strict;
use base 'DJabberd::Plugin';
use warnings;
use DBI;
use Digest::SHA1 qw(sha1_hex);
use MIME::Base64;
use LWP::Simple;

our $logger = DJabberd::Log->get_logger();

sub register {
    my ($self, $vhost) = @_;

    my $vcard_cb = sub {
        my ($vh, $cb, $iq) = @_;
        unless ($iq->isa("DJabberd::IQ")) {
            $cb->decline;
            return;
        }
        if (my $to = $iq->to_jid) {
            unless ($vhost->handles_jid($to)) {
                $cb->decline;
                return;
            }
        }
        if ($iq->signature eq 'get-{vcard-temp}vCard') {
            $self->get_vcard($vh, $iq);
            $cb->stop_chain;
            return;
        } elsif ($iq->signature eq 'set-{vcard-temp}vCard') {
            $self->set_vcard($vh, $iq);
            $cb->stop_chain;
            return;
        }
        $cb->decline;
    };

    $vhost->register_hook("switch_incoming_client", $vcard_cb);
    $vhost->register_hook("switch_incoming_server", $vcard_cb);

    warn "Registering hook!\n";
    $vhost->register_hook("AlterPresenceAvailable", sub {
        my (undef, $cb, $conn, $pkt) = @_;

        my $bj = $conn->bound_jid;
        unless ($bj) {
            $cb->done;
            return;
        }

        foreach my $ele ($pkt->children_elements) {
            next unless $ele->inner_ns eq "vcard-temp:x:update" && $ele->element_name eq "x";
            $pkt->remove_child($ele);
            last;
        }

        my $user = $bj->node;
        my $sha1_hex = get("http://www.livejournal.com/misc/jabber_userpic.bml?user=${user}&want=sha1");

        # append our fake one
        my $avatar = DJabberd::XMLElement->new("vcard-temp:x:update",
                                               "x",
                                               { '{}xmlns' => 'vcard-temp:x:update' },
                                               [
                                                DJabberd::XMLElement->new("vcard-temp:x:update",
                                                                          "photo",
                                                                          {},
                                                                          [$sha1_hex]),
                                                ]);
        $pkt->push_child($avatar);
        $cb->done;
    });
    $vhost->add_feature("vcard-temp");
}

sub get_vcard {
    my ($self, $vhost, $iq) = @_;

    my $user;
    if ($iq->to) {
        $user = $iq->to_jid->as_bare_string;
    } else {
        # user is requesting their own vCard
        $user = $iq->connection->bound_jid->as_bare_string;
    }

    my ($username) = $user =~ /^(\w+)\@/;

    my $mimetype;
    my $data = get("http://www.livejournal.com/misc/jabber_userpic.bml?user=${username}");
    die "No data for $user" unless $data;
    warn "Data length for $user = " . length($data) . "\n";

    my $b64 = encode_base64($data);

    if ($data =~ /^GIF/) {
        $mimetype = "image/gif";
    } elsif ($data =~ /^\x89PNG/) {
        $mimetype = "image/png";
    } else {
        $mimetype = 'image/jpeg';
    }

    $logger->info("Getting vcard for user '$user'");
    my $vcard = qq{<vCard xmlns='vcard-temp'>
    <PHOTO>
      <TYPE>$mimetype</TYPE>
      <BINVAL>
       $b64
      </BINVAL>
    </PHOTO>
    </vCard>};

    my $reply = $self->make_response($iq, $vcard);
    $reply->deliver($vhost);
}

sub make_response {
    my ($self, $iq, $vcard) = @_;

    my $response = $iq->clone;
    my $from = $iq->from;
    my $to   = $iq->to;
    $response->set_raw($vcard);

    $response->attrs->{"{}type"} = 'result';
    $response->set_to($from);
    $to ? $response->set_from($to) : delete($response->attrs->{"{}from"});

    return $response;
}

sub set_vcard {
    my ($self, $vhost, $iq) = @_;
    $iq->send_error;
}


1;
