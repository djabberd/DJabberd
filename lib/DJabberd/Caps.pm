package DJabberd::Caps;
# vim: sts=4 ai:
use strict;
use Digest::SHA;
use Carp;
use Encode;
use DJabberd::XMLElement;

use constant { HASH => 'sha-1' };

sub new {
    my $class = shift;
    my $self = bless { identity => [], feature => [], form => [], xml=>'', cap=>'' }, $class;
    foreach my$cap(@_) {
	next unless(ref($cap));
	$self->add($cap);
    }
    return $self;
}

sub add {
    my $self = shift;
    my $cap = shift;
    if(ref($cap) eq 'DJabberd::XMLElement') {
	if($cap->element_name eq 'identity') {
	    $cap = DJabberd::Caps::Identity->new($cap);
	} elsif($cap->element_name eq 'feature') {
	    $cap = DJabberd::Caps::Feature->new($cap);
	} elsif($cap->element eq '{jabber:x:data}x') {
	    $cap = DJabberd::Caps::Form->new($cap);
	}
    }
    return unless(UNIVERSAL::isa($cap,'DJabberd::Caps::Cap'));
    $self->{cap} = '';
    $self->{xml} = '';
    push(@{$self->{$cap->type}},$cap);
}

sub get {
    my $self = shift;
    my $type = shift;
    return @{exists $self->{$type} ? $self->{$type} : []};
}

sub as_cap {
    my $self = shift;
    if(!$self->{cap}) {
        my $ret = join('',map{$_->as_cap}sort{$a cmp $b}@{$self->{identity}});
        $ret .= join('',map{$_->as_cap}sort{$a cmp $b}@{$self->{feature}});
        $ret .= join('',map{$_->as_cap}sort{$a cmp $b}@{$self->{form}});
        $self->{cap} =  Encode::encode_utf8($ret);
    }
    return $self->{cap};
}

sub as_xml {
    my $self = shift;
    if(!$self->{xml}) {
        $self->{xml} = Encode::decode_utf8(
	     join('',@{$self->{identity}})
	    .join('',@{$self->{feature}})
	    .join('',@{$self->{form}})
        );
    }
    return $self->{xml};
}

sub digest {
    my $self = shift;
    my $hash = shift || HASH;
    my $ret;
    $hash =~ s/-//o;
    eval('$ret = Digest::SHA::'.$hash.'_base64($self->as_cap)');
    confess($@) if($@);
    $ret .= '=' while(length($ret) % 4);
    return $ret;
}

sub cap_xml {
    my $self = shift;
    my $node = shift;
    my $hash = shift || HASH;
    return "<c xmlns='http://jabber.org/protocol/caps' hash='$hash' node='$node' ver='".$self->digest($hash)."'/>";
}

package DJabberd::Caps::Cap;

sub type {
    croak(__PACKAGE__." must be overriden");
}

package DJabberd::Caps::Identity;
use base 'DJabberd::Caps::Cap';
use overload 'cmp' => \&cmp, '""' => \&as_xml;
use Carp;

sub type { 'identity' }

sub new {
    my $class = shift;
    my ($cat,$type,$name,$lang) = @_;
    if(!$type) {
	if(ref($cat) && UNIVERSAL::isa($cat,'DJabberd::XMLElement') && $cat->element_name eq type()) {
	    my $x = $cat;
	    $cat  = $x->attr('{}category');
	    $type = $x->attr('{}type');
	    $name = $x->attr('{}name');
	    $lang = $x->attr('{http://www.w3.org/XML/1998/namespace}lang');
	}
    } else {
	$name = Encode::decode_utf8($name);
    }
    croak("usage: $class".'->new($category, $type[, $name[, $lang]]) or ->new(DJabberd::XMLElement)') unless($cat && $type);
    return bless { category => $cat, type => $type, name => $name, lang => $lang}, $class;
}

sub cmp {
    my $self = shift;
    my $dude = shift;
    return ($self->{category} cmp $dude->{category} || $self->{type} cmp $dude->{type} || ($self->{lang} && $dude->{lang} && $self->{lang} cmp $dude->{lang}));
}

sub as_xml {
    my $self = shift;
    return '<identity category="'.$self->{category}.'" type="'.$self->{type}.'"'
	    .($self->{name} ? ' name="'.Encode::encode_utf8($self->{name}).'"'	: '')
	    .($self->{lang} ? ' xml:lang="'.$self->{lang}.'"'	: '')
	    .'/>';
}

sub as_element {
    my $self = shift;
    return DJabberd::XMLElement->new('','identity',{
		category => $self->{category},
		type => $self->{type},
		($self->{name} ? (name=>$self->{name}) : ()),
		($self->{lang} ? ('xml:lang' => $self->{lang}) : ())
	}, 
	[]
    );
}

sub as_cap {
    my $self = shift;
    return $self->{category}.'/'.$self->{type}.'/'.($self->{lang} || '').'/'.($self->{name} || '').'<';
}

sub bare {
    my $self = shift;
    my $ret = [ $self->{category}, $self->{type} ];
    push(@{$ret}, $self->{name}) if($self->{name});
    push(@{$ret}, $self->{lang}) if($self->{lang});
    return $ret;
}

package DJabberd::Caps::Feature;
use base 'DJabberd::Caps::Cap';
use overload 'cmp' => \&cmp, '""' => \&as_xml;
use Carp;

sub type { 'feature' }

sub new {
    my $class = shift;
    my $var;
    if(ref($_[0]) && UNIVERSAL::isa($_[0],'DJabberd::XMLElement') && $_[0]->element_name eq type()) {
	$var = $_[0]->attr('{}var');
    } else {
	$var = shift;
    }
    croak("Feature may not be empty") unless($var);
    return bless {var => $var}, $class; 
}

sub cmp {
    my $self = shift;
    my $dude = shift;
    return ($self->{var} cmp $dude->{var});
}

sub as_xml {
    my $self = shift;
    return '<feature var="'.$self->{var}.'"/>';
}

sub as_element {
    my $self = shift;
    return DJabberd::XMLElement->new('','feature',{var => $self->{var}},[]);
}

sub as_cap {
    my $self = shift;
    return $self->{var}.'<';
}

sub bare {
    my $self = shift;
    return $self->{var};
}

package DJabberd::Caps::Form;
use DJabberd::Form;
use base qw(DJabberd::Caps::Cap DJabberd::Form);
use overload 'cmp' => \&cmp;
use Carp;

sub type { 'form' }

sub cmp {
    my $self = shift;
    my $dude = shift;
    return (($self->{fields}->{FORM_TYPE}->{value}->[0] || '~'x9) cmp ($dude->{fields}->{FORM_TYPE}->{value}->[0] || '~'x9));
}

sub as_cap {
    my $self = shift;
    return '' unless(exists $self->{fields}->{FORM_TYPE} && ref($self->{fields}->{FORM_TYPE}));
    my $cap = $self->{fields}->{FORM_TYPE}->{value}->[0].'<';
    foreach my$f(sort{$a cmp $b}keys(%{$self->{fields}})) {
	next if($f eq 'FORM_TYPE');
	$cap .= ("$f<".join('<',@{$self->{fields}->{$f}->{value}}).'<');
    }
    return $cap;
}
1;
