package DJabberd::Roster;
use strict;
use warnings;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{items} = [];
    return $self;
}

sub add {
    my $self = shift;
    my $item = shift;
    die unless $item && $item->isa("DJabberd::RosterItem");
    push @{$self->{items}}, $item;
}

sub items {
    my $self = shift;
    return @{ $self->{items} };
}

sub from_items {
    my $self = shift;
    return grep { $_->subscription->sub_from } @{ $self->{items} };
}

sub to_items {
    my $self = shift;
    return grep { $_->subscription->sub_to } @{ $self->{items} };
}

sub as_xml {
    my $self = shift;
    my $xml = "<query xmlns='jabber:iq:roster'>";
    foreach my $it (@{ $self->{items} }) {
        next if $it->subscription->is_none_pending_in;
        $xml .= $it->as_xml;
    }
    $xml .= "</query>";
    return $xml;
}

1;
