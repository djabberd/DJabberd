package DJabberd::RosterItem;
use strict;
use Carp qw(croak);
use DJabberd::Util qw(exml);

use fields (
            'jid',
            'name',
            'groups',       # arrayref of group names
            'subscription', # subscription state
            );

sub new {
    my $self = shift;
    $self = fields::new($self) unless ref $self;
    if (@_ == 1) {
        $self->{jid} = $_[0];
    } else {
        my %opts = @_;
        $self->{jid}          = delete $opts{'jid'} or croak "No JID";
        $self->{name}         = delete $opts{'name'};
        $self->{groups}       = delete $opts{'groups'};
        $self->{subscription} = delete $opts{'subscription'};
        croak("unknown ctor fields: " . join(', ', keys %opts)) if %opts;
    }

    unless (ref $self->{jid}) {
        $self->{jid} = DJabberd::JID->new($self->{jid});
    }

    $self->{groups}       ||= [];
    $self->{subscription} ||= "none";
    return $self;
}

sub as_xml {
    my $self = shift;
    my $xml = "<item jid='" . exml($self->{jid}->as_bare_string) . "' subscription='" . exml($self->{subscription}) . "' ";
    if (defined $self->{name}) {
        $xml .= " name='" . exml($self->{name}) . "'";
    }
    $xml .= ">";
    foreach my $g (@{ $self->{groups} }) {
        $xml .= "<group>" . exml($g) . "</group>";
    }
    $xml .= "</item>";
    return $xml;
}


1;
