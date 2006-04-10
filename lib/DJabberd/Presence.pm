package DJabberd::Presence;
use strict;
use base qw(DJabberd::Stanza);
use Carp qw(confess);

sub process {
    confess "No generic 'process' method for $_[0]";
}

sub process_inbound {
    my ($self, $conn) = @_;

    my $is_client = $conn->isa("DJabberd::Connection::ClientIn");
    my $ns        = $is_client ? "{jabber:client}" : "{jabber:server}";
    my $type      = $self->attr("${ns}type");

    warn "$self PRESENCE INBOUND type='$type' from $conn not implemented\n";
}

sub process_outbound {
    my ($self, $conn) = @_;

    my $ns        = "{jabber:client}";
    my $type      = $self->attr("${ns}type");

    my $fail = sub {
        my $reason = shift;
        warn "PRESENCE FAILURE: $reason\n";
        return;
    };

    # user wanting to subscribe to target
    if ($type eq "subscribe") {
        my $to = $self->attr("${ns}to");
        my $contact_jid = DJabberd::JID->new($to)
            or return $fail->("no/invalid 'to' attribute");

        $conn->run_hook_chain(phase => "RosterSubscribe",
                              args  => [ $contact_jid ],
                              methods => {
                                  error   => sub {
                                      my ($cb, $reason) = @_;
                                      return $fail->("RosterSubscribe hook failed: $reason");
                                  },
                                  done => sub {
                                      # now send the packet to the other party
                                      $self->deliver($conn);
                                  },
                              },
                              fallback => sub {
                                  return $fail->("no RosterSubscriber hooks");
                              });

        return;
    }

    warn "$self PRESENCE OUTBOUND type='$type' from $conn not implemented\n";
}


1;
