package DJabberd::ClusterMessage::DeliverStanza;
use strict;
use warnings;
use base 'DJabberd::ClusterMessage';
use fields ('to',    # bare JID to deliver it to
            'asxml', # string representing the XML to send
            );

sub new {
    my $self = shift; # instance or class
    $self = fields::new($self) unless ref $self;

    my ($jid, $stanza) = @_;
    $self->{to}    = $jid->as_bare_string;
    $self->{asxml} = $stanza;  # TODO: ->as_xml, don't take raw object.  or both?
    return $self;
}

sub process {
    my ($self, $vhost) = @_;
    my @dconns = grep { $_->is_available } $vhost->find_conns_of_bare(DJabberd::JID->new($self->{to}));

    warn "Sending stanza to @dconns: [$self->{asxml}]\n";
    foreach my $c (@dconns) {
        $c->write(\ $self->{asxml});
    }
}

1;
