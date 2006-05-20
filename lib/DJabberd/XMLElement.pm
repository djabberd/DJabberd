package DJabberd::XMLElement;
use strict;
use fields (
            'ns',        # namespace name
            'element',   # element name
            'attrs',     # hashref of {namespace}attr => value
            'children',  # arrayref of child elements of this same type, or scalars for text nodes
            'raw',       # in some cases we have the raw xml and we have to create a fake XMLElement object
                         # business logic is that as_xml returns the raw stuff if it is exists, children has to be empty -- sky
            );

use DJabberd::Util;

sub new {
    my $class = shift;
    if (ref $_[0]) {
        # the down-classer that subclasses can inherit
        return bless $_[0], $class;
    }

    # constructing a new XMLElement:
    my ($ns, $elementname, $attrs, $children) = @_;

    Carp::confess("children isn't an arrayref, is: $children") unless ref $children eq "ARRAY";

    my $self = fields::new($class);
    $self->{ns}       = $ns;
    $self->{element}  = $elementname;
    $self->{attrs}    = $attrs;
    $self->{children} = $children;

    #DJabberd->track_new_obj($self);
    return $self;
}

#sub DESTROY {
#    my $self = shift;
#    DJabberd->track_destroyed_obj($self);
#}

sub set_raw {
    my DJabberd::XMLElement $self = shift;
    $self->{raw} = shift;
    $self->{children} = [];
}

sub children_elements {
    my DJabberd::XMLElement $self = shift;
    return grep { ref $_ } @{ $self->{children} };
}

sub children {
    my DJabberd::XMLElement $self = shift;
    return @{ $self->{children} };
}

sub first_child {
    my $self = shift;
    return @{ $self->{children} } ? $self->{children}[0] : undef;
}

sub first_element {
    my $self = shift;
    foreach my $c (@{ $self->{children} }) {
        return $c if ref $c;
    }
    return undef;
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
    my $self = shift;
    return ($self->{ns}, $self->{element}) if wantarray;
    return "{$self->{ns}}$self->{element}";
}

sub element_name {
    my $self = shift;
    return $self->{element};
}

sub namespace {
    my $self = shift;
    return $self->{ns};
}

sub as_xml {
    my $self = shift;
    my $nsmap = shift || {};  # localname -> uri, uri -> localname
    my $def_ns = shift;

    my ($ns, $el) = $self->element;

    my $attr_str = "";
    my $attr = $self->attrs;
    foreach my $k (keys %$attr) {
        next if $k eq "{}xmlns";
        my $value = $attr->{$k};
        # FIXME: ignoring all namespaces on attributes
        $k =~ s!^\{(.*)\}!!;
        my $ns = $1;
        $attr_str .= " $k='" . DJabberd::Util::exml($value) . "'";
    }

    my $xmlns = (!$ns ||
                 ($def_ns && $ns eq $def_ns) ||
                 $ns eq "jabber:server" ||
                 $ns eq "jabber:client") ?
                 "" : " xmlns='$ns'";
    my $innards = $self->innards_as_xml($nsmap, $ns, $def_ns);
    $innards = "..." if $DJabberd::ASXML_NO_INNARDS && $innards;
    return length $innards ?
        "<$el$xmlns$attr_str>$innards</$el>" :
        "<$el$xmlns$attr_str/>";
}

sub innards_as_xml {
    my $self = shift;
    my $nsmap = shift || {};
    my $def_ns = shift;

    if ($self->{raw}) {
        return $self->{raw};
    }

    my $ret = "";
    foreach my $c ($self->children) {
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
    return $clone;
}

1;
