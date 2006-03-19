package DJabberd::Roster::LiveJournal;
use strict;
use base 'DJabberd::Roster';

sub register {
    my ($self, $server) = @_;
    $server->register_hook("getroster", sub {
        my ($conn, $cb) = @_;

        my $items;
        my $friends = LWP::Simple::get("http://www.livejournal.com/misc/fdata.bml?user=" . $self->{username});
        foreach my $line (sort split(/\n/, $friends)) {
            next unless $line =~ m!> (\w+)!;
            my $fuser = $1;
            $items .= "<item jid='$fuser\@$conn->{server_name}' name='$fuser' subscription='both'><group>Friends</group></item>\n";
        }
        $cb->set_roster_body($items);
    });
}

1;
