package DJabberd::JID;
use strict;
use DJabberd::Util qw(exml);
use Digest::SHA;

# Configurable via 'CaseSensitive' config option
our $CASE_SENSITIVE = 0;

use overload
    '""' => \&as_string_exml;

use constant NODE       => 0;
use constant DOMAIN     => 1;
use constant RES        => 2;
use constant AS_STRING  => 3;
use constant AS_BSTRING => 4;
use constant AS_STREXML => 5;

# Stringprep functions for converting to canonical form
use Unicode::Stringprep;
use Unicode::Stringprep::Mapping;
use Unicode::Stringprep::Prohibited;
my $nodeprep = Unicode::Stringprep->new(
    3.2,
    [
        \@Unicode::Stringprep::Mapping::B1,
        \@Unicode::Stringprep::Mapping::B2,
    ],
    'KC',
    [
        \@Unicode::Stringprep::Prohibited::C11,
        \@Unicode::Stringprep::Prohibited::C12,
        \@Unicode::Stringprep::Prohibited::C21,
        \@Unicode::Stringprep::Prohibited::C22,
        \@Unicode::Stringprep::Prohibited::C3,
        \@Unicode::Stringprep::Prohibited::C4,
        \@Unicode::Stringprep::Prohibited::C5,
        \@Unicode::Stringprep::Prohibited::C6,
        \@Unicode::Stringprep::Prohibited::C7,
        \@Unicode::Stringprep::Prohibited::C8,
        \@Unicode::Stringprep::Prohibited::C9,
        [
            0x0022, undef, # "
            0x0026, undef, # &
            0x0027, undef, # '
            0x002F, undef, # /
            0x003A, undef, # :
            0x003C, undef, # <
            0x003E, undef, # >
            0x0040, undef, # @
        ]
    ],
    1,
);
my $nameprep = Unicode::Stringprep->new(
    3.2,
    [
        \@Unicode::Stringprep::Mapping::B1,
        \@Unicode::Stringprep::Mapping::B2,
    ],
    'KC',
    [
        \@Unicode::Stringprep::Prohibited::C12,
        \@Unicode::Stringprep::Prohibited::C22,
        \@Unicode::Stringprep::Prohibited::C3,
        \@Unicode::Stringprep::Prohibited::C4,
        \@Unicode::Stringprep::Prohibited::C5,
        \@Unicode::Stringprep::Prohibited::C6,
        \@Unicode::Stringprep::Prohibited::C7,
        \@Unicode::Stringprep::Prohibited::C8,
        \@Unicode::Stringprep::Prohibited::C9,
    ],
    1,
);
my $resourceprep = Unicode::Stringprep->new(
    3.2,
    [
        \@Unicode::Stringprep::Mapping::B1,
    ],
    'KC',
    [
        \@Unicode::Stringprep::Prohibited::C12,
        \@Unicode::Stringprep::Prohibited::C21,
        \@Unicode::Stringprep::Prohibited::C22,
        \@Unicode::Stringprep::Prohibited::C3,
        \@Unicode::Stringprep::Prohibited::C4,
        \@Unicode::Stringprep::Prohibited::C5,
        \@Unicode::Stringprep::Prohibited::C6,
        \@Unicode::Stringprep::Prohibited::C7,
        \@Unicode::Stringprep::Prohibited::C8,
        \@Unicode::Stringprep::Prohibited::C9,
    ],
    1,
);


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
           (?: /(.{1,1023})   )?                                           # $3: optional resource
           $!x;

    # If we're in case-sensitive mode, for backwards-compatibility,
    # then skip stringprep
    return bless [ $1, $2, $3 ], $_[0] if $DJabberd::JID::CASE_SENSITIVE;

    # Stringprep uses regexes, so store these away first
    my ($node, $host, $res) = ($1, $2, $3);

    return eval {
        bless [
            defined $node ? $nodeprep->($node) : undef,
            $nameprep->($host),
            defined $res  ? $resourceprep->($res) : undef,
        ], $_[0]
    };
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

sub as_string_exml {
    my $self = $_[0];
    return $self->[AS_STREXML] ||=
        exml($self->as_string);
}

sub as_bare_string {
    my $self = $_[0];
    return $self->[AS_BSTRING] ||=
        join('',
             ($self->[NODE] ? ($self->[NODE], '@') : ()),
             $self->[DOMAIN]);
}

sub rand_resource {
    Digest::SHA::sha1_hex(rand() . rand() . rand());
}

1;

