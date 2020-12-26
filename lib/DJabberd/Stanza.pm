package DJabberd::Stanza;
use strict;
use base qw(DJabberd::XMLElement);
use Carp qw(croak);
use fields (
            'connection',   # Store the connection the stanza came in on so we can respond.
                            # may be undef, as it's a weakref.  if you want to mess with the
                            # structure, you can't do so unless you're the owner, so clone
                            # it first otherwise.
            '_memo_tojid',   # memoized to jid
            '_memo_fromjid', # memoized from jid
            );

sub downbless {
    my $class = shift;
    if (ref $_[0]) {
        my ($self, $conn) = @_;
        my $new = fields::new($class);
        %$new = %$self; # copy fields
        if ($conn) {
            $new->{connection} = $conn;
            Scalar::Util::weaken($new->{connection});
        }
        return $new;
    } else {
        croak("Bogus use of downbless.");
    }

}

sub as_summary {
    my $self = shift;
    return "[Stanza of type " . $self->element_name . " to " . $self->to_jid->as_string . "]";
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
    return 0 unless $conn->peer_domain_is_verified($from->domain);
    #return 0 unless $conn->vhost;  FIXME?  yes?
    return 1;
}

sub delivery_failure {
    my ($self, $vh, $reason) = @_;
    #warn "$self has no ->delivery_failure method implemented\n";
}

sub to {
    my DJabberd::Stanza $self = shift;
    return $self->{attrs}{"{}to"};
}

sub from {
    my DJabberd::Stanza $self = shift;
    return $self->{attrs}{"{}from"};
}

sub to_jid {
    my DJabberd::Stanza $self = shift;
    return $self->{_memo_tojid} ||= DJabberd::JID->new($self->{attrs}{"{}to"});
}

sub from_jid {
    my DJabberd::Stanza $self = shift;
    return $self->{_memo_fromjid} ||= DJabberd::JID->new($self->{attrs}{"{}from"});
}

sub set_from {
    #my ($self, $from) = @_;
    my DJabberd::Stanza $self = $_[0];
    $self->{_memo_fromjid} = undef;
    $self->{attrs}{"{}from"} = ref $_[1] ? $_[1]->as_string : $_[1];
}

sub set_to {
    #my ($self, $to) = @_;
    my DJabberd::Stanza $self = $_[0];
    $self->{_memo_tojid} = undef;
    $self->{attrs}{"{}to"} = ref $_[1] ? $_[1]->as_string : $_[1];
}

sub deliver_when_unavailable {
    0;
}

sub make_response {
    my ($self) = @_;

    # Common to all stanzas is a switching of the from/to addresses.
    my $response = $self->clone;
    my $from = $self->from;
    my $to   = $self->to;

    $response->set_to($from);
    $to ? $response->set_from($to) : delete($response->attrs->{"{}from"});
    
    $response->set_raw("");

    return $response;
}

sub make_error_response {
    my ($self, $code, $type, $error) = @_;
    
    my $response = $self->clone;
    my $from = $self->from;
    my $to   = $self->to;

    $response->set_to($from);
    $to ? $response->set_from($to) : delete($response->attrs->{"{}from"});

    my $error_elem = new DJabberd::XMLElement(
        $self->namespace,
        "error",
        {
            "{}code" => $code,
            "{}type" => $type,
        },
        [
            ref $error ? $error : new DJabberd::XMLElement("urn:ietf:params:xml:ns:xmpp-stanzas", $error, {}, []),
        ],
    );

    $response->attrs->{"{}type"} = "error";
    $response->push_child($error_elem);
    
    return $response;
}

1;
