package DJabberd::Roster;
use strict;
use warnings;

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    $self->{items}      = [];
    $self->{cache_gets} = 0;   # times retrieved from cache

    return $self;
}

sub inc_cache_gets {
    return ++$_[0]->{cache_gets};
}

sub cache_gets {
    return $_[0]->{cache_gets};
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
    return grep { !$_->remove && $_->subscription->sub_from } @{ $self->{items} };
}

sub to_items {
    my $self = shift;
    return grep { !$_->remove && $_->subscription->sub_to } @{ $self->{items} };
}

sub as_xml {
    my $self = shift;
    my $ver = (@{$self->{items}} && $self->{items}->[-1]->ver)? " ver='".$self->{items}->[-1]->ver."'":'';
    my $xml = "<query xmlns='jabber:iq:roster'$ver";
    if(@{$self->{items}}) {
        $xml .= ">";
        foreach my $it (@{ $self->{items} }) {
            next if $it->subscription->is_none_pending_in || $it->remove;
            $xml .= $it->as_xml;
        }
        $xml .= "</query>";
    } else {
        $xml .= "/>";
    }
    return $xml;
}

1;
