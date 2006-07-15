
# "Journals" component for LiveJournal.
#
# A playground for cool weblog-related XMPP/Jabber tech

package DJabberd::Plugin::LiveJournal::JournalComponent;

use strict;
use warnings;
use base qw(DJabberd::Component);
use DJabberd::Plugin::LiveJournal::JournalComponent::PersonalJournal;
use DJabberd::Plugin::LiveJournal::JournalComponent::CommunityJournal;
use DJabberd::Log;
use LWP::UserAgent;
use HTTP::Request;

our $logger = DJabberd::Log->get_logger();

# NOTE: This is all pretty-much lame at the moment.
#   When I get my LJ dev environment back up and running again, I'll
#   make this all use gearman rather than this crap.

sub get_node {
    my ($self, $nodename) = @_;

    # Journal names can only contain \w characters
    return undef if $nodename =~ /\W/;

    $self->{journaltype_cache} ||= {};

    my $journaltype = $self->{journaltype_cache}{$nodename};

    unless ($journaltype) {
        # LAME LAME LAME LAME
        my $ua = new LWP::UserAgent;
        my $req = new HTTP::Request("GET" => "http://$nodename.livejournal.com/data/foaf");
        my $res = $ua->request($req);

        if ($res->is_success) {

            my $content = substr($res->content, 0, 512);

            # MORE LAME
            if ($content =~ /<foaf:Person/) {
                $journaltype = 'P';
            }
            elsif ($content =~ /<foaf:Group/) {
                $journaltype = 'C';
            }
        }
    }
    
    $self->{journaltype_cache}{$nodename} = $journaltype;
    
    if ($journaltype eq 'P') {
        return DJabberd::Plugin::LiveJournal::JournalComponent::PersonalJournal->new(component => $self, nodename => $nodename);
    }
    elsif ($journaltype eq 'C') {
        return DJabberd::Plugin::LiveJournal::JournalComponent::CommunityJournal->new(component => $self, nodename => $nodename);
    }

    return undef;
}

# This will probably move into gearman-land later, and will then return a $u object rather than a username
sub get_effective_user {
    my ($self, $jid) = @_;
    
    # TEMP: allow my dev domain as well as LiveJournal.com
    return $jid->node if $jid->node =~ /^\w+$/ && $jid->domain eq 'livejournal.com';
    return undef;
}

sub child_services {
    my ($self, $remote_jid) = @_;
    
    my $remote_user = $self->get_effective_user($remote_jid);
    return [] unless defined($remote_user);
    
    # The child services returned are the journals (personal and community) on
    # the user's friends list.

    # LAME LAME LAME LAME
    my $ua = new LWP::UserAgent;
    my $req = new HTTP::Request("GET" => "http://www.livejournal.com/misc/fdata.bml?user=".$remote_user);
    my $res = $ua->request($req);

    my @friends = ();

    if ($res->is_success) {
        my $content = $res->content;
        push @friends, $1 while ($content =~ /> (\w+)\b/gs);
    }
    
    # Just fake up some community watches since I can't be bothered parsing FOAF data
    my @communities = qw(lj_dev changelog s2styles);
    
    return [
        map({ [ $_."@".$self->domain, "$_ community" ] } @communities),
        map({ [ $_."@".$self->domain, "${_}'s journal" ] } @friends)
    ];

}

1;

