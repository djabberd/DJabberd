package DJabberd::XMLElement;
use strict;
use fields (
            'ns',        # namespace name
            'element',   # element name
            'attrs',     # hashref of {namespace}attr => value.  NOTE: used by Stanza.pm directly.
            'children',  # arrayref of child elements of this same type, or scalars for text nodes
            'raw',       # in some cases we have the raw xml and we have to create a fake XMLElement object
                         # business logic is that as_xml returns the raw stuff if it is exists, children has to be empty -- sky
            'prefix',    # namepace prefix in use in this element
            );

use DJabberd::Util;

sub new {
    my $class = shift;
    if (ref $_[0]) {
        # the down-classer that subclasses can inherit
        return bless $_[0], $class;
    }

    # constructing a new XMLElement:
    my DJabberd::XMLElement $self = fields::new($class);
    ($self->{ns},
     $self->{element},
     $self->{attrs},
     $self->{children},
     $self->{raw},
     $self->{prefix}) = @_;
    #my ($ns, $elementname, $attrs, $children) = @_;
    #Carp::confess("children isn't an arrayref, is: $children") unless ref $children eq "ARRAY";

    #DJabberd->track_new_obj($self);
    return $self;
}

#sub DESTROY {
#    my $self = shift;
#    DJabberd->track_destroyed_obj($self);
#}

sub push_child {
    my DJabberd::XMLElement $self = $_[0];
    push @{$self->{children}}, $_[1]; # $node
}

sub set_raw {
    my DJabberd::XMLElement $self = shift;
    $self->{raw} = shift;
    $self->{children} = [];
}

sub children_elements {
    my DJabberd::XMLElement $self = $_[0];
    return grep { ref $_ } @{ $self->{children} };
}

sub remove_child {
    my DJabberd::XMLElement $self = $_[0];
    @{$self->{children}} = grep { $_ != $_[1] } @{$self->{children}};
}

sub children {
    my DJabberd::XMLElement $self = $_[0];
    return @{ $self->{children} };
}

sub first_child {
    my DJabberd::XMLElement $self = $_[0];
    return @{ $self->{children} } ? $self->{children}[0] : undef;
}

sub first_element {
    my DJabberd::XMLElement $self = $_[0];
    foreach my $c (@{ $self->{children} }) {
        return $c if ref $c;
    }
    return undef;
}

sub inner_ns {
    return $_[0]->{attrs}{'{}xmlns'};
}

sub attr {
    return $_[0]->{attrs}{$_[1]};
}

sub set_attr {
    $_[0]->{attrs}{$_[1]} = $_[2];
}

sub attrs {
    return $_[0]->{attrs};
}

sub element {
    my DJabberd::XMLElement $self = $_[0];
    return ($self->{ns}, $self->{element}) if wantarray;
    return "{$self->{ns}}$self->{element}";
}

sub element_name {
    my DJabberd::XMLElement $self = $_[0];
    return $self->{element};
}

sub namespace {
    my DJabberd::XMLElement $self = $_[0];
    return $self->{ns};
}

sub replace_ns {
    my ($self, $fromns, $tons) = @_;
    if ($self->{ns} eq $fromns) {
        $self->{ns} = $tons;
    }
    foreach my $child ($self->children_elements()) {
        $child->replace_ns($fromns, $tons);
    }
}

sub _resolve_prefix {
    my ($self, $nsmap, $def_ns, $uri, $attr) = @_;
    if ($def_ns && $def_ns eq $uri) {
        return '';
    } elsif ($uri eq '') {
        return '';
    } elsif ($nsmap->{$uri}) {
        $nsmap->{$uri} . ':';
    } else {
        $nsmap->{___prefix_count} ||= 0;
        my $count = $nsmap->{___prefix_count}++;
        my $prefix = "nsp$count";
        $nsmap->{$uri} = $prefix;
        $nsmap->{$prefix} = $uri;
        $attr->{'{http://www.w3.org/2000/xmlns}' . $prefix} = $uri;
        return $prefix . ':';
    }
}

sub as_xml {
    my DJabberd::XMLElement $self = shift;

    my $nsmap = shift || { }; # localname -> uri, uri -> localname

    # tons of places call as_xml, but nobody seems to care about
    # the default namespace. It seems, however, that it is a common
    # usage for "jabber:client" to be this default ns.
    my $def_ns = shift || 'jabber:client';

    my ($ns, $el) = ($self->{ns}, $self->{element});
    if ($self->{prefix}) {
        $nsmap->{ $self->{prefix} } = $ns;
        $nsmap->{$ns} = $self->{prefix};
    }

    my $attr_str = "";
    my $attr = $self->{attrs};

    $nsmap->{xmlns} = 'http://www.w3.org/2000/xmlns';
    $nsmap->{'http://www.w3.org/2000/xmlns'} = 'xmlns';
    $nsmap->{xml} = 'http://www.w3.org/XML/1998/namespace';
    $nsmap->{'http://www.w3.org/XML/1998/namespace'} = 'xml';

    # let's feed the nsmap...
    foreach my $k (keys %$attr) {
        if ($k =~ /^\{(.*)\}(.+)$/) {
            my ($nsuri, $name) = ($1, $2);
            if ($nsuri eq 'xmlns' ||
                $nsuri eq 'http://www.w3.org/2000/xmlns/') {
                $nsmap->{$name} = $attr->{$k};
                $nsmap->{ $attr->{$k} } = $name;
            } elsif ($k eq '{}xmlns') {
                $def_ns = $attr->{$k};
            }
        } elsif ($k eq 'xmlns') {
            $def_ns = $attr->{$k};
        }
    }

    my $nsprefix = $self->_resolve_prefix($nsmap, $def_ns, $ns, $attr);

    foreach my $k (keys %$attr) {
        my $value = $attr->{$k};
        if ($k =~ /^\{(.*)\}(.+)$/) {
            my ($nsuri, $name) = ($1, $2);
            if ($nsuri eq 'xmlns' ||
                $nsuri eq 'http://www.w3.org/2000/xmlns/') {
                $attr_str .= " xmlns:$name='" . DJabberd::Util::exml($value)
                          . "'";
            } elsif ($k eq '{}xmlns') {
                $attr_str .= " xmlns='" . DJabberd::Util::exml($value) . "'";
            } else {
                my $nsprefix = $self->_resolve_prefix($nsmap, $def_ns, $nsuri);
                $attr_str .= " $nsprefix$name='" . DJabberd::Util::exml($value)
                          ."'";
            }
        } else {
            $attr_str .= " $k='" . DJabberd::Util::exml($value) . "'";
        }
    }

    my $innards = $self->innards_as_xml($nsmap, $def_ns);
    $innards = "..." if $DJabberd::ASXML_NO_INNARDS && $innards;

    my $result = length $innards ?
        "<$nsprefix$el$attr_str>$innards</$nsprefix$el>" :
        "<$nsprefix$el$attr_str/>";

    return $result;

}

sub innards_as_xml {
    my DJabberd::XMLElement $self = shift;
    my $nsmap = shift || {};
    my $def_ns = shift;

    if ($self->{raw}) {
        return $self->{raw};
    }

    my $ret = "";
    foreach my $c (@{ $self->{children} }) {
        if (ref $c) {
            $ret .= $c->as_xml($nsmap, $def_ns);
        } else {
            if ($DJabberd::ASXML_NO_TEXT) {
                $ret .= "...";
            } else {
                $ret .= DJabberd::Util::exml($c);
            }
        }
    }
    return $ret;
}

sub clone {
    my $self = shift;
    my $clone = fields::new(ref($self));
    $clone->{ns}       = $self->{ns};
    $clone->{element}  = $self->{element};
    $clone->{attrs}    = { %{ $self->{attrs} } };
    $clone->{children} = [ map { ref($_) ? $_->clone : $_ } @{ $self->{children} } ];
    $clone->{raw}      = $self->{raw};
    $clone->{prefix}   = $self->{prefix};
    return $clone;
}

1;
