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

sub as_xml {
    my $self = shift;
    my $xml = "<query xmlns='jabber:iq:roster'>";
    foreach my $it (@{ $self->{items} }) {
        $xml .= $it->as_xml;
    }
    $xml .= "</query>";
    return $xml;
}

1;
