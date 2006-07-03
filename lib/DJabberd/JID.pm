package DJabberd::JID;
use strict;

use overload
    '""' => \&as_string;

use constant NODE       => 0;
use constant DOMAIN     => 1;
use constant RES        => 2;
use constant AS_STRING  => 3;
use constant AS_BSTRING => 4;

# returns DJabberd::JID object, or undef on failure due to invalid format
sub new {
    #my ($class, $jidstring) = @_;

    # The following regex is loosely based on the EBNF grammar in
    # JEP-0029. This JEP has actually been retracted, but seems to be
    # the only reasonable spec for JID syntax.

    # NOTE: Currently this only supports US-ASCII characters.

    return undef unless $_[1] && $_[1] =~
        m!^(?: ([\x29\x23-\x25\x28-\x2E\x30-\x39\x3B\x3D\x3F\x41-\x7E]{1,1023}) \@)? # $1: optional node
           ([a-zA-Z0-9\.\-]{1,1023})                                                 # $2: domain
           (?: /([\x21-\x7e]{1,1023})   )?                                           # $3: optional resource
           $!x;

    return bless [ $1, $2, $3 ], $_[0];
}

sub is_bare {
    return $_[0]->[RES] ? 0 : 1;
}

sub node {
    return $_[0]->[NODE];
}

sub domain {
    return $_[0]->[DOMAIN];
}

sub resource {
    return $_[0]->[RES];
}

sub eq {
    my ($self, $jid) = @_;
    return $jid && $self->as_string eq $jid->as_string;
}

sub as_string {
    my $self = $_[0];
    return $self->[AS_STRING] ||=
        join('',
             ($self->[NODE] ? ($self->[NODE], '@') : ()),
             $self->[DOMAIN],
             ($self->[RES] ? ('/', $self->[RES]) : ()));
}

sub as_bare_string {
    my $self = $_[0];
    return $self->[AS_BSTRING] ||=
        join('',
             ($self->[NODE] ? ($self->[NODE], '@') : ()),
             $self->[DOMAIN]);
}

1;

