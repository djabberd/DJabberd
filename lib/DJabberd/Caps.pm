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
    my $self = bless { identity => [], feature => [], form => []}, $class;
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
    push(@{$self->{$cap->type}},$cap);
}

sub get {
    my $self = shift;
    my $type = shift;
    return @{exists $self->{$type} ? $self->{$type} : []};
}

sub as_cap {
    my $self = shift;
    my $ret = join('',map{$_->as_cap}sort{$a cmp $b}@{$self->{identity}});
    $ret .= join('',map{$_->as_cap}sort{$a cmp $b}@{$self->{feature}});
    $ret .= join('',map{$_->as_cap}sort{$a cmp $b}@{$self->{form}});
    return Encode::encode_utf8($ret);
}

sub as_xml {
    my $self = shift;
    return   Encode::decode_utf8(
	     join('',@{$self->{identity}})
	    .join('',@{$self->{feature}})
	    .join('',@{$self->{form}})
    );
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
use base 'DJabberd::Caps::Cap';
use overload 'cmp' => \&cmp, '""' => \&as_xml;
use Carp;

sub type { 'form' }

sub new {
    my $class = shift;
    my $self;
    # Try to create from XMLElement tree
    if(@_ && $_[0] && ref($_[0]) && UNIVERSAL::isa($_[0],'DJabberd::XMLElement') && $_[0]->element eq '{jabber:x:data}x' && $_[0]->children) {
	$self = from_element($_[0]);
    } else {
	# Or from raw struct
	my $type = shift;
	my $fields = shift;
	my %args = @_;
	if($type && ref($fields) eq 'ARRAY' && @{$fields}) {
	    $self = { type => $type, fields => {}, order => []};
	    foreach my$f(@{$fields}) {
		if(ref($f) eq 'HASH' && $f->{var} && ref($f->{value}) eq 'ARRAY') {
		    push(@{$self->{order}},$f->{var});
		    $self->{fields}->{$f->{var}} = $f;
		}
	    }
	    $self->{title} = $args{title} if($args{title});
	    $self->{instructions} = $args{instructions} if(ref($args{instructions}) eq 'ARRAY');
	}
    }
    croak("Form may not be empty") unless(ref($self) eq 'HASH' && @{$self->{order}});
    return bless $self, $class; 
}
sub from_element {
    my $x = shift;
    my @inst;
    my $title;
    my %field;
    my @order;
    foreach my$el($x->children_elements) {
	if($el->element_name eq 'title') {
	    $title = $el->innards_as_xml;
	} elsif($el->element_name eq 'instructions') {
	    push(@inst,$el->innards_as_xml);
	} elsif($el->element_name eq 'field') {
	    my $field = {
		var => $el->attr('{}var'),
		type => $el->attr('{}type'),
		label => $el->attr('{}label'),
		value => [],
		option => []
	    };
	    foreach my$c($el->children_elements) {
		if($c->element_name eq 'desc') {
		    $field->{desc} = $c->innards_as_xml;
		} elsif($c->element_name eq 'required') {
		    $field->{required} = 1;
		} elsif($c->element_name eq 'value') {
		    push(@{$field->{value}},$c->innards_as_xml);
		} elsif($c->element_name eq 'option') {
		    my $option = { value => $c->first_element->innards_as_xml };
		    $option->{label} = $c->attr('{}label') if($c->attr('{}label'));
		    push(@{$field->{option}},$option);
		}
	    }
	    push(@order,$field->{var});
	    $field{$field->{var}} = $field;
	}
    }
    return {type => $x->attr('{}type'), title => $title, instructions => \@inst, fields => \%field, order => \@order};
}
sub cmp {
    my $self = shift;
    my $dude = shift;
    return (($self->{fields}->{FORM_TYPE}->{value}->[0] || '~'x9) cmp ($dude->{fields}->{FORM_TYPE}->{value}->[0] || '~'x9));
}
sub as_xml {
    my $self = shift;
    my $xml = '<x xmlns="jabber:x:data" type="'.$self->{type}.'">';
    $xml .= ('<title>'.$self->{title}.'</title>') if($self->{title});
    foreach my$i(@{$self->{instructions}}) {
	$xml .= "<instructions>$i</instructions>";
    }
    foreach my$v(@{$self->{order}}) {
	$xml .= '<field var="'.$self->{fields}->{$v}->{var}.'"'
		.($self->{fields}->{$v}->{type} ? ' type="'.$self->{fields}->{$v}->{type}.'"':'')
		.($self->{fields}->{$v}->{label} ? ' label="'.$self->{fields}->{$v}->{label}.'"':'')
		.'>';
	$xml .= ('<desc>'.$self->{fields}->{$v}->{desc}.'</desc>') if($self->{fields}->{$v}->{desc});
	$xml .= ('<required/>') if($self->{fields}->{$v}->{required});
	foreach my$k(@{$self->{fields}->{$v}->{value}}) {
	    $xml .= "<value>$k</value>";
	}
	foreach my$k(@{$self->{fields}->{$v}->{option}}) {
	    $xml .= '<option'.($k->{label} ? ' label="'.$k->{label}.'"':'').'><value>'.$k->{value}.'</value></option>';
	}
	$xml .= '</field>';
    }
    return "$xml</x>";
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
sub as_element {
    my $self = shift;
    my @innards;
    push(@innards,DJabberd::XMLElement->new('','title',{},[$self->{title}])) if($self->{title});
    foreach my$i(@{$self->{instructions}}) {
	push(@innards,DJabberd::XMLElement->new('','instructions',{},[$i]));
    }
    foreach my$v(@{$self->{order}}) {
	my $attr = { var => $v };
	$attr->{type} = $self->{fields}->{$v}->{type} if($self->{fields}->{$v}->{type});
	$attr->{label} = $self->{fields}->{$v}->{label} if($self->{fields}->{$v}->{label});
	my $kids = [];
	push(@{$kids},DJabberd::XMLElement->new('','desc',{},[$self->{fields}->{$v}->{desc}])) if($self->{fields}->{$v}->{desc});
	push(@{$kids},DJabberd::XMLElement->new('','required',{},[])) if($self->{fields}->{$v}->{required});
	foreach my$k(@{$self->{fields}->{$v}->{value}}) {
	    push(@{$kids},DJabberd::XMLElement->new('','value',{},[$k]));
	}
	foreach my$k(@{$self->{fields}->{$v}->{option}}) {
	    my $oa = {};
	    $oa->{label} = $k->{label} if($k->{label});
	    push(@{$kids},DJabberd::XMLElement->new('','option',$oa,[DJabberd::XMLElement->new('','value',{},[$k->{value}])]));
	}
	push(@innards,DJabberd::XMLElement->new('','field',$attr,$kids));
    }
    return DJabberd::XMLElement->new('','x',{xmlns=>'jabber:x:data'},\@innards);
}
1;
