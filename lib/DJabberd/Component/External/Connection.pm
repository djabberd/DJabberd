
=head1 NAME

DJabberd::Component::External::Component - Connection component for DJabberd::Component::External

=head1 INTRODUCTION

This class provides the connection and stream handling implementation for the
DJabberd component DJabberd::Component::External. It is of no interest on its own.

=head1 LICENCE

Copyright 2006 Martin Atkins and Six Apart

This library is part of the Jabber server DJabberd. It can be modified and distributed
under the same terms as DJabberd itself.

=cut

package DJabberd::Component::External::Connection;
use strict;
use base 'DJabberd::Connection';
use DJabberd::Log;
use Digest::SHA1;

our $logger = DJabberd::Log->get_logger();

use fields (
    'authenticated',   # boolean - whether component has completed the authentication handshake
    'cmpnt_handler',   # reference to the Component::External object that we belong to
);

sub new {
    my ($class, $socket, $server, $handler) = @_;

    $logger->debug("Making a $class for fd %d.\n", fileno($socket));
    
    my $self = $class->SUPER::new($socket, $server);

    $self->{authenticated} = 0;
    $self->{cmpnt_handler} = $handler;
    Scalar::Util::weaken($self->{cmpnt_handler});
    
    return $self;
}

sub close {
    my $self = shift;
    return if $self->{closed};
    
    $self->{cmpnt_handler}->handle_component_disconnect($self);    

    $self->SUPER::close;
}

sub namespace {
    return "jabber:component:accept";
}

sub on_stream_start {
    my DJabberd::Component::External::Connection $self = shift;
    my $ss = shift;
    return $self->close unless $ss->xmlns eq $self->namespace; # FIXME: should be stream error

    $logger->debug("Got stream start for component ".$ss->to);

    $self->{in_stream} = 1;

    my $correct_domain = $self->{cmpnt_handler}->domain;

    # JEP-0114 says the component should put its domain name in the "to" attribute,
    # but the py*t family of transports seems to put it in "from" instead.
    my $claimed_domain = $ss->to || $ss->from;

    # FIXME: This dies if the domain is wrong and it came from $ss->from
    return $self->close_no_vhost($claimed_domain) unless ($claimed_domain eq $correct_domain);

    $self->set_vhost($self->{cmpnt_handler}->vhost);

    $self->start_stream_back($ss,
        namespace  => 'jabber:component:accept',
    );
}

sub is_server { 1 }

sub is_authenticated {
    return $_[0]->{authenticated};
}

my %element2class = (
    "{jabber:component:accept}iq"       => 'DJabberd::IQ',
    "{jabber:component:accept}message"  => 'DJabberd::Message',
    "{jabber:component:accept}presence" => 'DJabberd::Presence',
);

sub on_stanza_received {
    my ($self, $node) = @_;

    if ($self->xmllog->is_info) {
        $self->log_incoming_data($node);
    }

    unless ($self->{authenticated}) {
        my $type = $node->element;
        
        if ($type eq '{urn:ietf:params:xml:ns:xmpp-tls}starttls') {
            my $stanza = DJabberd::Stanza::StartTLS->downbless($node, $self);
            $stanza->process($self);
            return;
        }
        
        unless ($type eq '{jabber:component:accept}handshake') {
            $logger->warn("Component sent $type stanza before handshake. Discarding.");
            return;
        }
        
        my $innards = $node->innards_as_xml();
        $innards =~ s/^\s+//g;
        $innards =~ s/\s+$//g;
        
        # So what should the correct hash be?
        # FIXME: This probably doesn't handle escaping/encodings properly,
        #    so make sure the stream ID and secret are US-ASCII and don't use XML
        #    reserved characters!
        my $correct = lc(Digest::SHA1::sha1_hex($self->stream_id.$self->{cmpnt_handler}->secret));
        
        if ($correct eq $innards) {
            # DJabberd::Connection is allergic to elements without 'to' attributes, so just send this raw
            $self->write('<handshake/>');
            $self->{authenticated} = 1;
        }
        else {
            $logger->warn("Got bad handshake from component. Disconnecting. ".$self->stream_id.$self->{cmpnt_handler}->secret);
            return $self->stream_error('not-authorized', 'The supplied digest was invalid');
        }
    
        return;
    }

    my $class = $element2class{$node->element} or return $self->stream_error("unsupported-stanza-type");

    # same variable as $node, but down(specific)-classed.
    my $stanza = $class->downbless($node, $self);

    $self->{cmpnt_handler}->handle_component_stanza($stanza);
}

1;
