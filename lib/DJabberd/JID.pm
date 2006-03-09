package DJabber::JID;

# returns DJabberd::JIB object, or undef on failure due to invalid format
sub new {
    my ($class, $jidstring) = @_;

    # {=jidformat}, {=jidsizes}
    return undef unless $jidstring =~
        m!^(?: (\w{1,1023}) \@)?     # optional node
           ([^/]{1,1023})            # domain
           (?: /(.{1,1023})   )?     # optional resource
           !x;

    my ($node, $domain, $resource) = ($1, $2, $3);

    return bless {
        'node'     => $node,
        'domain'   => $domain,
        'resource' => $resource,
    }, $class;
}

sub as_string {
    my $self = shift;
    return $self->{_as_string} ||=
        join('',
             ($self->{node} ? ($self->{'node'}, '@') : ()),
             $self->{domain},
             ($self->{resource} ? ('/', $self->{'resource'}) : ()));
}

sub as_bare_string {
    my $self = shift;
    return $self->{_as_bare_string} ||=
        join('',
             ($self->{node} ? ($self->{'node'}, '@') : ()),
             $self->{domain});
}

1;

