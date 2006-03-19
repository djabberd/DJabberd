package DJabberd::SAXHandler;
use strict;
use base qw(XML::SAX::Base);
use DJabberd::XMLElement;
use DJabberd::StreamStart;

sub new {
    my ($class, $client) = @_;
    my $self = $class->SUPER::new;
    $self->{"ds_client"} = $client;
    $self->{"capture_depth"} = 0;  # on transition from 1 to 0, stop capturing
    $self->{"on_end_capture"} = undef;  # undef or $subref->($doc)
    $self->{"events"} = [];  # capturing events
    return $self;
}

sub start_element {
    my $self = shift;
    my $data = shift;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, ["start_element", $data];
        $self->{capture_depth}++;
        return;
    }

    my $ds = $self->{ds_client};

    # {=xml-stream}
    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {

        my $ss = DJabberd::StreamStart->new($data);
        $ds->on_stream_start($ss);
        return;
    }

    my $start_capturing = sub {
        my $cb = shift;

        $self->{"events"} = [];  # capturing events
        $self->{capture_depth} = 1;

        # capture via saving SAX events
        push @{$self->{events}}, ["start_element", $data];

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
        push @{$self->{events}}, ["characters", $data];
    }
}

sub end_element {
    my ($self, $data) = @_;

    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {
        $self->{ds_client}->end_stream;
        return;
    }

    if ($self->{capture_depth}) {
        push @{$self->{events}}, ["end_element", $data];
        $self->{capture_depth}--;
        return if $self->{capture_depth};
        my $doc = undef;
        if (my $cb = $self->{on_end_capture}) {
            $cb->($doc, $self->{events});
        }
        return;
    }

    #print Dumper("END", $data);
}

sub _nodes_from_events {
    my $evlist = shift;  # don't modify
    #my $tree = ["namespace", "element", \%attr, [ <children>* ]]

    my @events = @$evlist;  # our copy
    my $nodelist = [];

    my $handle_chars = sub {
        my $ev = shift;
        my $text = $ev->[1]{Data};
        if (@$nodelist == 0 || ref $nodelist->[-1]) {
            push @$nodelist, $text;
        } else {
            $nodelist->[-1] .= $text;
        }
    };

    my $handle_element = sub {
        my $ev = shift;
        my $depth = 1;
        my @children = ();
        while (@events && $depth) {
            my $child = shift @events;
            push @children, $child;

            if ($child->[0] eq "start_element") {
                $depth++;
                next;
            } elsif ($child->[0] eq "end_element") {
                $depth--;
                next if $depth;
                pop @children;  # this was our own element
            }
        }
        die "Finished events without reaching depth 0!" if !@events && $depth;

        my $ns = $ev->[1]{NamespaceURI};

        # clean up the attributes from SAX
        my $attr_sax = $ev->[1]{Attributes};
        my $attr = {};
        foreach my $key (keys %$attr_sax) {
            my $val = $attr_sax->{$key}{Value};
            my $fkey = $key;
            if ($fkey =~ s!^\{\}!!) {
                next if $fkey eq "xmlns";
                $fkey = "{$ns}$fkey";
            }
            $attr->{$fkey} = $val;
        }

        my $localname = $ev->[1]{LocalName};
        my $ele = DJabberd::XMLElement->new($ns, $localname, $attr, _nodes_from_events(\@children));
        push @$nodelist, $ele;
    };

    while (@events) {
        my $ev = shift @events;
        if ($ev->[0] eq "characters") {
            $handle_chars->($ev);
            next;
        }

        if ($ev->[0] eq "start_element") {
            $handle_element->($ev);
            next;
        }

        die "Unknown event in stream: $ev->[0]\n";
    }
    return $nodelist;
}


1;
