package DJabberd::XMLElement;
use strict;
use constant ELEMENT  => 0;
use constant ATTRS    => 1;
use constant CHILDREN => 2;

use DJabberd::Util;

sub new {
    my ($class, $node) = @_;
    return bless $node, $class;
}

sub children {
    my $self = shift;
    return @{ $self->[CHILDREN] };
}

sub first_child {
    my $self = shift;
    return @{ $self->[CHILDREN] } ? $self->[CHILDREN][0] : undef;
}

sub first_element {
    my $self = shift;
    foreach my $c (@{ $self->[CHILDREN] }) {
        return $c if ref $c;
    }
    return undef;
}

sub attr {
    return $_[0]->[ATTRS]{$_[1]};
}

sub attrs {
    return $_[0]->[ATTRS];
}

sub element {
    return $_[0]->[ELEMENT] unless wantarray;
    my $el = $_[0]->[ELEMENT];
    $el =~ /^\{(.+)\}(.+)/;
    return ($1, $2);

}

sub as_xml {
    my $self = shift;
    my $nsmap = shift || {};  # localname -> uri, uri -> localname
    my $def_ns = shift;

    my ($ns, $el) = $self->element;

    # FIXME: escaping
    my $attr_str = "";
    my $attr = $self->attrs;
    foreach my $k (keys %$attr) {
        my $value = $attr->{$k};
        $k =~ s!^\{(.+)\}!!;
        my $ns = $1;
        $attr_str .= " $k='" . DJabberd::Util::exml($value) . "'";
    }

    my $xmlns = $ns eq $def_ns ? "" : " xmlns='$ns'";
    my $innards = $self->innards_as_xml($nsmap, $ns);
    return length $innards ?
        "<$el$xmlns$attr_str>$innards</$el>" :
        "<$el$xmlns$attr_str/>";
}

sub innards_as_xml {
    my $self = shift;
    my $nsmap = shift || {};
    my $def_ns = shift;

    my $ret = "";
    foreach my $c ($self->children) {
        if (ref $c) {
            $ret .= $c->as_xml($nsmap, $def_ns);
        } else {
            $ret .= $c;
        }
    }
    return $ret;
}

1;
