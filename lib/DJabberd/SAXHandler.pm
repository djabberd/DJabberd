package DJabberd::SAXHandler;
use strict;
use base qw(XML::SAX::Base);
use DJabberd::XMLElement;
use DJabberd::StreamStart;
use Scalar::Util qw(weaken);
use Time::HiRes ();

sub new {
    my ($class, $conn) = @_;
    my $self = $class->SUPER::new;

    if ($conn) {
        $self->{"ds_conn"} = $conn;
        weaken($self->{ds_conn});
    }

    $self->{"capture_depth"} = 0;  # on transition from 1 to 0, stop capturing
    $self->{"on_end_capture"} = undef;  # undef or $subref->($doc)
    $self->{"events"} = [];  # capturing events
    return $self;
}

sub set_connection {
    my ($self, $conn) = @_;
    $self->{ds_conn} = $conn;
    if ($conn) {
        weaken($self->{ds_conn});
    } else {
        # when sax handler is being put back onto the freelist...
        $self->{on_end_capture} = undef;
    }
}

# called when somebody is about to destroy their reference to us, to make
# us clean up.
sub cleanup {
    my $self = shift;
    $self->{on_end_capture} = undef;
}

sub depth {
    return $_[0]{capture_depth};
}

use constant EVT_START_ELEMENT => 1;
use constant EVT_END_ELEMENT   => 2;
use constant EVT_CHARS         => 3;

sub start_element {
    my ($self, $data) = @_;
    my $conn = $self->{ds_conn};

    # {=xml-stream}
    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {

        my $ss = DJabberd::StreamStart->new($data);

        # when Connection.pm is prepping a new dummy root node, we legitimately
        # get here without a connection, so we need to test for it:
        $conn->on_stream_start($ss) if $conn;
        return;
    }

    # need a connection past this point.
    return unless $conn;

    # if they're not in a stream yet, bail.
    unless ($conn->{in_stream}) {
        $conn->stream_error('invalid-namespace');
        return;
    }

    if ($self->{capture_depth}) {
        push @{$self->{events}}, [EVT_START_ELEMENT, $data];
        $self->{capture_depth}++;
        return;
    }

    # start capturing...
    $self->{"events"} = [
                         [EVT_START_ELEMENT, $data],
                         ];
    $self->{capture_depth} = 1;

    Scalar::Util::weaken($conn);
    $self->{on_end_capture} = sub {
        my ($doc, $events) = @_;
        my $nodes = _nodes_from_events($events);
        # {=xml-stanza}
        my $t1 = Time::HiRes::time();
        $conn->on_stanza_received($nodes->[0]) if $conn;
        my $td = Time::HiRes::time() - $t1;

        # ring buffers for latency stats:
        if ($td > $DJabberd::Stats::latency_log_threshold) {
            $DJabberd::Stats::stanza_process_latency_log[ $DJabberd::Stats::latency_log_index =
                                                          ($DJabberd::Stats::latency_log_index + 1)
                                                          % $DJabberd::Stats::latency_log_max_size
                                                          ] = [$td, $nodes->[0]->as_xml];
        }

        $DJabberd::Stats::stanza_process_latency[ $DJabberd::Stats::latency_index =
                                                  ($DJabberd::Stats::latency_index + 1)
                                                   % $DJabberd::Stats::latency_max_size
                                                  ] = $td;
    };
    return;
}

sub characters {
    my ($self, $data) = @_;

    if ($self->{capture_depth}) {
        push @{$self->{events}}, [EVT_CHARS, $data];
    }

    # TODO: disconnect client if character data between stanzas?  as
    # long as it's not whitespace, because that's permitted as a
    # keep-alive.

}

sub end_element {
    my ($self, $data) = @_;

    if ($data->{NamespaceURI} eq "http://etherx.jabber.org/streams" &&
        $data->{LocalName} eq "stream") {
        $self->{ds_conn}->end_stream if $self->{ds_conn};
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
