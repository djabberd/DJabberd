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

sub on_recv_from_server {
    my ($self, $conn) = @_;
    $self->deliver($conn->vhost);
}

sub process {
    my ($self, $conn) = @_;
    die "$self ->process not implemented\n";
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
    my ($stanza, $arg) = @_;

    # arg can be a connection, vhost, or nothing.  TODO: kinda ghetto.  fix callers?
    my $vhost;
    if (UNIVERSAL::isa($arg, "DJabberd::VHost")) {
        $vhost = $arg;
    } elsif (UNIVERSAL::isa($arg, "DJabberd::Connection")) {
        $vhost = $arg->vhost;
    } elsif ($stanza->{connection}) {
        $vhost = $stanza->{connection}->vhost;
    }
    Carp::croak("Can't determine vhost delivering: " . $stanza->as_xml) unless $vhost;

    $vhost->hook_chain_fast("deliver",
                            [ $stanza ],
                            {
                               delivered => sub { },
                               # FIXME: in future, this should note deliver was
                               # complete and the next message to this jid should be dequeued and
                               # subsequently delivered.  (in order deliver)
                               error => sub {
                                   my $reason = $_[1];
                                   $stanza->delivery_failure($vhost, $reason);
                               },
                           },
                           sub {
                               $stanza->delivery_failure($vhost);
                           });
}

# by default, stanzas need to and from coming from a server
sub acceptable_from_server {
    my ($self, $conn) = @_;  # where $conn is a serverin connection
    my ($to, $from) = ($self->to_jid, $self->from_jid);
    return 0 unless $to && $from;
    return 0 unless $from->domain eq $conn->peer_domain;
    #return 0 unless $conn->vhost;  FIXME?  yes?
    return 1;
}

sub delivery_failure {
    my ($self, $vh, $reason) = @_;
    #warn "$self has no ->delivery_failure method implemented\n";
}

sub to {
    my $self = shift;
    return $self->attr("{}to");
}

sub from {
    my $self = shift;
    return $self->attr("{}from");
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
    my ($self, $from) = @_;
    return $self->set_attr("{}from", ref $from ? $from->as_string : $from);
}

sub set_to {
    my ($self, $to) = @_;
    return $self->set_attr("{}to", ref $to ? $to->as_string : $to);
}

1;
