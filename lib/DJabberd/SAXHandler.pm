package DJabberd::SAXHandler;
use strict;
use base qw(XML::SAX::Base);
use DJabberd::XMLElement;
use DJabberd::StreamStart;
use Scalar::Util qw(weaken);

sub new {
    my ($class, $client) = @_;
    my $self = $class->SUPER::new;
    $self->{"ds_client"} = $client;
    weaken($self->{ds_client});

    $self->{"capture_depth"} = 0;  # on transition from 1 to 0, stop capturing
    $self->{"on_end_capture"} = undef;  # undef or $subref->($doc)
    $self->{"events"} = [];  # capturing events
    return $self;
}

use constant EVT_START_ELEMENT => 1;
use constant EVT_END_ELEMENT   => 2;
use constant EVT_CHARS         => 3;

sub start_element {
    my ($self, $data) = @_;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, [EVT_START_ELEMENT, $data];
        $self->{capture_depth}++;
        return;
    }

    # if we don't have a ds_client (Connection object), then connection
    # is dead and events don't matter.
    my $ds = $self->{ds_client} or
        return;

    # {=xml-stream}
    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {

        my $ss = DJabberd::StreamStart->new($data);
        $ds->on_stream_start($ss);
        return;
    }

    # FIXME: close connection harshly if the first thing we get isn't a stream start.
    # basically, ask the $ds client object if it's expecting an opening stream,
    # then we also do the right thing after ssl/sasl

    my $start_capturing = sub {
        my $cb = shift;

        $self->{"events"} = [];  # capturing events
        $self->{capture_depth} = 1;

        # capture via saving SAX events
        push @{$self->{events}}, [EVT_START_ELEMENT, $data];

        $self->{on_end_capture} = $cb;
        return 1;
    };

    return $start_capturing->(sub {
        my ($doc, $events) = @_;
        my $nodes = _nodes_from_events($events);
        # {=xml-stanza}
        $ds->on_stanza_received($nodes->[0]);
    });

}

sub characters {
    my ($self, $data) = @_;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, [EVT_CHARS, $data];
    }
}

sub end_element {
    my ($self, $data) = @_;

    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {
        $self->{ds_client}->end_stream if $self->{ds_client};
        return;
    }

    if ($self->{capture_depth}) {
        push @{$self->{events}}, [EVT_END_ELEMENT, $data];
        $self->{capture_depth}--;
        return if $self->{capture_depth};
        my $doc = undef;
        if (my $cb = $self->{on_end_capture}) {
            $cb->($doc, $self->{events});
        }
        return;
    }
}

sub _nodes_from_events {
    my ($evlist, $i, $end) = @_;
    $i   ||= 0;
    $end ||= scalar @$evlist;
    my $nodelist = [];    # what we're returning (nodes are text or XMLElement nodes)

    while ($i < $end) {
        my $ev = $evlist->[$i++];

        if ($ev->[0] == EVT_CHARS) {
            my $text = $ev->[1]{Data};
            if (@$nodelist == 0 || ref $nodelist->[-1]) {
                push @$nodelist, $text;
            } else {
                $nodelist->[-1] .= $text;
            }
            next;
        }

        if ($ev->[0] == EVT_START_ELEMENT) {
            my $depth = 1;
            my $start_idx = $i;  # index of first potential body node

            while ($depth && $i < $end) {
                my $child = $evlist->[$i++];

                if ($child->[0] == EVT_START_ELEMENT) {
                    $depth++;
                } elsif ($child->[0] == EVT_END_ELEMENT) {
                    $depth--;
                }
            }
            die "Finished events without reaching depth 0!" if $depth;

            my $end_idx = $i - 1;  # (end - start) == number of child elements

            my $attr_sax = $ev->[1]{Attributes};
            my $attr = {};
            while (my $key = each %$attr_sax) {
                $attr->{$key} = $attr_sax->{$key}{Value};
            }

            push @$nodelist, DJabberd::XMLElement->new($ev->[1]{NamespaceURI},
                                                       $ev->[1]{LocalName},
                                                       $attr,
                                                       _nodes_from_events($evlist, $start_idx, $end_idx));
            next;
        }

        die "Unknown event in stream: $ev->[0]\n";
    }
    return $nodelist;
}


1;
