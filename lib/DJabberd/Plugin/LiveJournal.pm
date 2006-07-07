package DJabberd::Plugin::LiveJournal;
use strict;
use base 'DJabberd::Plugin';
use warnings;
use Digest::SHA1 qw(sha1_hex);
use MIME::Base64;
use Gearman::Client::Async;

use LWP::Simple;

our $logger = DJabberd::Log->get_logger();

our $gearman_client;
sub gearman_client {
    return $gearman_client;
}

sub set_config_gearmanservers {
    my ($self, $val) = @_;
    my @list = split(/\s*,\s*/, $val);
    $gearman_client = Gearman::Client::Async->new;
    $gearman_client->set_job_servers(@list);
}

sub register {
    my ($self, $vhost) = @_;

    my $hook_vcard = sub {
        $self->hook_vcard_switch(@_);
    };

    $vhost->register_hook("switch_incoming_client", $hook_vcard);
    $vhost->register_hook("switch_incoming_server", $hook_vcard);
    $vhost->register_hook("OnInitialPresence",      \&hook_on_initial_presence);
    $vhost->register_hook("AlterPresenceAvailable", \&hook_alter_presence);
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

    my $gc = DJabberd::Plugin::LiveJournal->gearman_client;
    unless ($gc) {
        $iq->send_error;
        return;
    }

    $gc->add_task(Gearman::Task->new("ljtalk_avatar_data" => \ "$username", {
        uniq        => "-",
        retry_count => 2,
        timeout     => 10,
        on_fail     => sub { $iq->send_error },
        on_complete => sub {
            my $dataref = shift;
            unless ($$dataref) {
                $iq->send_error;
                return;
            }

            my $data = $$dataref;
            my $mimetype;
            warn "Data length for $user = " . length($data) . "\n";

            my $b64 = encode_base64($data);

            if ($data =~ /^GIF/) {
                $mimetype = "image/gif";
            } elsif ($data =~ /^\x89PNG/) {
                $mimetype = "image/png";
            } else {
                $mimetype = 'image/jpeg';
            }

            my $vcard = qq{<vCard xmlns='vcard-temp'>
                               <N><GIVEN>$username</GIVEN></N>
                               <PHOTO>
                               <TYPE>$mimetype</TYPE>
                               <BINVAL>$b64</BINVAL>
                               </PHOTO>
                               </vCard>};

            my $reply = $self->make_response($iq, $vcard);
            $reply->deliver($vhost);
            return;
        },
    }));
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

sub hook_on_initial_presence {
    my (undef, $cb, $conn) = @_;
    my $bj = $conn->bound_jid;
    my $how_much = $bj->node =~ /^whitaker|revmischa|brad|crucially|supersat|mart|scsi|evan$/ ?
        "more than Whitaker's mom" :
        "a lot";

    $conn->write("<message to='$bj' from='livejournal.com' type='headline'><body>LJ Talk is currently a pre-alpha service lacking tons of features and probably with a bunch of bugs.

We're actively developing it, constantly restarting it with new stuff.  So just don't be surprised if the service goes up and down $how_much.</body></message>");
}

sub hook_vcard_switch {
    my ($self, $vhost, $cb, $iq) = @_;
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
        $self->get_vcard($vhost, $iq);
        $cb->stop_chain;
        return;
    } elsif ($iq->signature eq 'set-{vcard-temp}vCard') {
        $iq->send_error;
        $cb->stop_chain;
        return;
    }
    $cb->decline;
}

sub hook_alter_presence {
    my (undef, $cb, $conn, $pkt) = @_;

    my $bj = $conn->bound_jid;
    my $gc = DJabberd::Plugin::LiveJournal->gearman_client;

    unless ($bj && $gc) {
        $cb->done;
        return;
    }

    foreach my $ele ($pkt->children_elements) {
        next unless ($ele->inner_ns || '') eq "vcard-temp:x:update" && $ele->element_name eq "x";
        $pkt->remove_child($ele);
        last;
    }

    my $user = $bj->node;

    $gc->add_task(Gearman::Task->new("ljtalk_avatar_sha1" => \ "$user", {
        uniq        => "-",
        retry_count => 2,
        timeout     => 10,
        on_fail     => sub { $cb->done },
        on_complete => sub {
            my $sha1ref = shift;

            # append our fake one
            my $avatar = DJabberd::XMLElement->new("vcard-temp:x:update",
                                                   "x",
                                                   { '{}xmlns' => 'vcard-temp:x:update' },
                                                   [
                                                    DJabberd::XMLElement->new("vcard-temp:x:update",
                                                                              "photo",
                                                                              {},
                                                                              [$$sha1ref]),
                                                    ]);
            $pkt->push_child($avatar);
            $cb->done;
        },
    }));
}

1;
