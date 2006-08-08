package DJabberd::Plugin::LiveJournal;
use strict;
use base 'DJabberd::Plugin';
use warnings;
use Digest::SHA1 qw(sha1_hex);
use MIME::Base64;
use Gearman::Client::Async;
use Gearman::Client;
use LWP::Simple;

our $logger = DJabberd::Log->get_logger();

my $start_time = time();

our @gearman_servers;
our $gearman_client;
sub gearman_client {
    return $gearman_client;
}

sub set_config_gearmanservers {
    my ($self, $val) = @_;
    @gearman_servers = split(/\s*,\s*/, $val);
    $gearman_client = Gearman::Client::Async->new;
    $gearman_client->set_job_servers(@gearman_servers);
}

sub register {
    my ($self, $vhost) = @_;

    my $hook_vcard = sub {
        $DJabberd::Stats::counter{'debug_iq_leak1_c2s'}++;
        $self->hook_vcard_switch(@_, "c2s");
    };

    my $hook_vcard_s2s = sub {
        $DJabberd::Stats::counter{'debug_iq_leak1_s2s'}++;
        $self->hook_vcard_switch(@_, "s2s");
    };

    $vhost->register_hook("switch_incoming_client", $hook_vcard);
    $vhost->register_hook("switch_incoming_server", $hook_vcard_s2s);
    $vhost->register_hook("OnInitialPresence",      \&hook_on_initial_presence);
    $vhost->register_hook("AlterPresenceAvailable", \&hook_alter_presence);
    $vhost->register_hook("AlterPresenceUnavailable", \&hook_alter_presence);
    $vhost->register_hook("ConnectionClosing", \&hook_connection_closing);
    $vhost->add_feature("vcard-temp");

    # make sure we init this cluster node when it comes up
    my $gc = Gearman::Client->new;
    $gc->job_servers(@gearman_servers);
    my $rv = $gc->do_task("ljtalk_init", $vhost->server_name . "_cluster_ip_port", {timeout => 5});
    die "Couldn't init LJ Plugin" unless $$rv eq 'OK';

}

sub get_vcard_keyword {
    my ($self, $jid, $last_bcast) = @_;
    $last_bcast ||= DJabberd::Presence->local_presence_info($jid);
    my $keyword;
    if (keys %$last_bcast) {
        foreach my $value (values %$last_bcast) {
            foreach my $ele ($value->children_elements) {
                if ($ele->element_name eq 'status') {
                    $keyword = $ele->first_child;
                }
                last;
            }
        }
    }
    return $keyword;
}


sub get_vcard {
    my ($self, $vhost, $iq) = @_;

    my $user;
    my $user_iq;
    if ($iq->to) {
        unless ($iq->to_jid) {
            # some clients, like sim 0.9.3 send incorrect to jids, in that case to is set but to_jid is undef
            # the jid constructor should really deal with this for us, but currently it doesn't  FIXME!
            $iq->send_error;
            return;
        }
        $user = $iq->to_jid->as_bare_string;
        $user_iq = $iq->to_jid;
    } else {
        # user is requesting their own vCard
        $user = $iq->connection->bound_jid->as_bare_string;
        $user_iq = $iq->connection->bound_jid;
    }

    my ($username) = $user =~ /^(\w+)\@/;

    my $gc = DJabberd::Plugin::LiveJournal->gearman_client;
    unless ($gc) {
        $iq->send_error;
        return;
    }


    my $keyword = $self->get_vcard_keyword($user_iq);

    $gc->add_task(Gearman::Task->new("ljtalk_avatar_data" => \Storable::nfreeze([$username, $keyword]), {
        uniq        => "-",
        retry_count => 2,
        timeout     => 10,
        on_fail     => sub {
            $DJabberd::Stats::counter{'ljtalk_avatar_data_fail'}++;
            $iq->send_error;
        },
        on_complete => sub {
            my $dataref = shift;
            unless ($$dataref) {
                $iq->send_error;
                return;
            }

            my $data = $$dataref;
            my $mimetype;

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

    my $gc = DJabberd::Plugin::LiveJournal->gearman_client;
    unless ($gc) {
        return;
    }

    my $bj = $conn->bound_jid;
    my $username = $bj->node;

    $gc->add_task(Gearman::Task->new("ljtalk_user_motd" => \Storable::nfreeze([$username]), {
        uniq        => "-",
        retry_count => 2,
        timeout     => 10,
        on_fail     => sub {
            $DJabberd::Stats::counter{'ljtalk_user_motd_fail'}++;
        },
        on_complete => sub {
            my $dataref = shift;
            if (length $$dataref) {
                $conn->write( "<message to='$bj' from='livejournal.com' type='headline'>".
                              $$dataref.
                              "</message>"
                              );
            }
       }
    }));
}

sub hook_vcard_switch {
    my ($self, $vhost, $cb, $iq, $type) = @_;
    $DJabberd::Stats::counter{"debug_iq_leak2_$type"}++;
    unless ($iq->isa("DJabberd::IQ")) {
        $DJabberd::Stats::counter{"debug_iq_leak3_$type"}++;
        $cb->decline;
        return;
    }
    if (my $to = $iq->to_jid) {
        $DJabberd::Stats::counter{"debug_iq_leak4_$type"}++;
        unless ($vhost->handles_jid($to)) {
            $DJabberd::Stats::counter{"debug_iq_leak5_$type"}++;
            $cb->decline;
            return;
        }
    }
    if ($iq->signature eq 'get-{vcard-temp}vCard') {
        $DJabberd::Stats::counter{"debug_iq_leak6_$type"}++;
        $self->get_vcard($vhost, $iq);
        $cb->stop_chain;
        return;
    } elsif ($iq->signature eq 'set-{vcard-temp}vCard') {
        $DJabberd::Stats::counter{"debug_iq_leak7_$type"}++;
        $iq->send_error;
        $cb->stop_chain;
        return;
    }

    $DJabberd::Stats::counter{"debug_iq_leak8_$type"}++;
    $cb->decline;
}

sub hook_connection_closing {
    my (undef, $cb, $conn) = @_;

    my $bj = $conn->bound_jid;
    my $gc = DJabberd::Plugin::LiveJournal->gearman_client;

    unless ($bj && $gc) {
        $cb->declined;
        return;
    }

    $gc->add_task(Gearman::Task->new("ljtalk_connection_closing" => \Storable::nfreeze([$bj->node, $bj->resource]), {
                                     uniq => '-',
                                     retry_count => 2,
                                     timeout => 10,
                                     on_fail => sub {
                                         $DJabberd::Stats::counter{'ljtalk_alter_presence_fail'}++;
                                     },
                                     on_complete => sub {
                                         $DJabberd::Stats::counter{'ljtalk_alter_presence_success'}++;
                                     },
                                 }));

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


    my $priority;
    foreach my $ele ($pkt->children_elements) {
        if ($ele->element_name eq 'priority') {
            $priority = $ele->first_child;
        }
        next unless ($ele->inner_ns || '') eq "vcard-temp:x:update" && $ele->element_name eq "x";
        $pkt->remove_child($ele);
        last;
    }

    my $user = $bj->node;

    $gc->add_task(Gearman::Task->new("ljtalk_alter_presence" => \Storable::nfreeze([$bj->node, $bj->resource, $priority,  $pkt->as_xml]), {
                                     uniq => '-',
                                     retry_count => 2,
                                     timeout => 10,
                                     on_fail => sub {
                                         $DJabberd::Stats::counter{'ljtalk_alter_presence_fail'}++;
                                     },
                                     on_complete => sub {
                                         $DJabberd::Stats::counter{'ljtalk_alter_presence_success'}++;
                                     },
                                 }));

    my $keyword = __PACKAGE__->get_vcard_keyword($bj, { dummy => $pkt });


    $gc->add_task(Gearman::Task->new("ljtalk_avatar_sha1" => \Storable::nfreeze([$user, $keyword]), {
        uniq        => "-",
        retry_count => 2,
        timeout     => 10,
        on_fail     => sub {
            $DJabberd::Stats::counter{'ljtalk_avatar_sha1_fail'}++;
            $cb->done;
        },
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
