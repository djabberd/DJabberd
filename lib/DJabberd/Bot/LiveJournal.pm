package DJabberd::Bot::LiveJournal;
use strict;
use warnings;
use base 'DJabberd::Bot';
use Chatbot::Eliza;
use DJabberd::Util qw(exml);

our $logger = DJabberd::Log->get_logger();

sub process_text {
    my ($self, $text, $from, $ctx) = @_;

    my $gc = DJabberd::Plugin::LiveJournal->gearman_client;
    unless ($gc) {
        $ctx->reply("ERROR: no gearman client configured");
        return;
    }

    my $html = $ctx->last_html;

    my $req = Storable::nfreeze({
        user => $from->node,
        text => $text,
        html => $html,
    });

    $gc->add_task(Gearman::Task->new("ljtalk_bot_talk" => \$req, {
        retry_count => 2,
        timeout     => 20,
        on_fail     => sub {
            $DJabberd::Stats::counter{'ljtalk_bot_talk_fail'}++;
            $ctx->reply("Error talking to goat.  He must've fallen asleep.  Say it again?");
        },
        on_complete => sub {
            my $stref = shift;
            my $res = eval { Storable::thaw($$stref) };
            if ($res->{text}) {
                $ctx->reply($res->{text}, $res->{html});
            } else {
                $ctx->reply("ok.");
            }
        },
    }));
}

1;


