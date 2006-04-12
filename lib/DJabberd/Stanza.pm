package DJabberd::Stanza;
use strict;
use base qw(DJabberd::XMLElement);
use Carp qw(croak);
use fields (
            'connection',   # Store the connection the stanza came in on so we can respond.
                            # may be undef, as it's a weakref.  if you want to mess with the
                            # structure, you can't do so unless you're the owner, so clone
                            # it first otherwise.
            );

sub downbless {
    my $class = shift;
    if (ref $_[0]) {
        my ($self, $conn) = @_;
        # 'fields' hackery.  this will break in Perl 5.10
        {
            no strict 'refs';
            $self->[0] = \%{$class . "::FIELDS" }
        }
        bless $self, $class;
        if ($conn) {
            $self->{connection} = $conn;
            Scalar::Util::weaken($self->{connection});
        }
        return $self;
    } else {
        croak("Bogus use of downbless.");
    }

}

sub process {
    my ($self, $conn) = @_;
    warn "$self ->process not implemented\n";
}

sub connection {
    my $self = shift;
    return $self->{connection};
}

sub set_connection {
    my ($self, $conn) = @_;
    $self->{connection} = $conn;
}

# at this point, it's assumed the stanza has passed filtering checks,
# and should be delivered.
sub deliver {
    my ($stanza, $conn) = @_;

    $conn->run_hook_chain(phase => "deliver",
                          args  => [ $stanza ],
                          methods => {
                              delivered => sub { },
                              # FIXME: in future, this should note deliver was
                              # complete and the next message to this jid should be dequeued and
                              # subsequently delivered.  (in order deliver)
                          },
                          fallback => sub {
                              $stanza->delivery_failure($conn);
                          });
}

# by default, stanzas need to and from coming from a server
sub acceptable_from_server {
    my ($self, $conn) = @_;  # where $conn is a serverin connection
    my ($to, $from) = ($self->to_jid, $self->from_jid);
    return 0 unless $to && $from;
    return 0 unless $from->domain eq $conn->peer_domain;
    return 1;
}

sub delivery_failure {
    my ($self, $conn) = @_;
    warn "$self has no ->delivery_failure method implemented\n";
}

sub to {
    my $self = shift;
    return
        $self->attr("{jabber:client}to") ||
        $self->attr("{jabber:server}to") ||
        $self->attr("{}to");
}

sub from {
    my $self = shift;
    return
        $self->attr("{jabber:client}from") ||
        $self->attr("{jabber:server}from") ||
        $self->attr("{}from");
}

sub to_jid {
    my $self = shift;
    return DJabberd::JID->new($self->to);
}

sub from_jid {
    my $self = shift;
    return DJabberd::JID->new($self->from);
}

sub set_from {
    my ($self, $fromstr) = @_;
    my $ns = $self->namespace;
    return $self->set_attr("{$ns}from", $fromstr);
}

sub set_to {
    my ($self, $to) = @_;
    my $ns = $self->namespace;
    return $self->set_attr("{$ns}to", ref $to ? $to->as_string : $to);
}

1;
