package DJabberd::Form;
# vim: sts=4 ai:
use strict;
use DJabberd::XMLElement;
use overload '""' => \&as_xml;
use Carp qw(croak);

our @field_types = (
    'boolean',
    'fixed',
    'hidden',
    'jid-multi',
    'jid-single',
    'list-multi',
    'list-single',
    'text-multi',
    'text-private',
    'text-single'
);
sub new {
    my $class = shift;
    my $self;
    # Try to create from XMLElement tree
    if(@_ && $_[0] && ref($_[0]) && UNIVERSAL::isa($_[0],'DJabberd::XMLElement') && $_[0]->element eq '{jabber:x:data}x' && $_[0]->children) {
	$self = from_element($_[0]);
    } else {
	# Or from raw struct: new('type',[{var=>"var",value=>["val"]},...],[title=>"title",][instructions=>"instructions"]);
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
	    if($field->{type} && !grep{$_ eq $field->{type}}@field_types) {
		warn "Unsupported field type ".$field->{type};
		return undef;
	    }
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

sub field {
    my $self = shift;
    my $name = shift;
    return $self->{fields}->{$name};
}

sub value {
    my $self = shift;
    my $name = shift;
    return ((exists $self->{fields}->{$name} && $self->{fields}->{$name}->{value}) ? 
	    @{$self->{fields}->{$name}->{value}}
	    : ());
}

sub type {
    my $self = shift;
    return $self->{type};
}

sub form_type {
    my $self = shift;
    my $type = '';
    if(exists $self->{fields}->{FORM_TYPE}) {
	if(($self->{fields}->{FORM_TYPE}->{type} && $self->{fields}->{FORM_TYPE}->{type} eq 'hidden')
	  || $self->{type} eq 'submit')
	{
	    $type = $self->{fields}->{FORM_TYPE}->{value}->[0];
	}
    }
    return $type;
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

sub as_element {
    my $self = shift;
    my @innards;
    my $ns = 'jabber:x:data';
    push(@innards,DJabberd::XMLElement->new($ns,'title',{},[$self->{title}])) if($self->{title});
    foreach my$i(@{$self->{instructions}}) {
	push(@innards,DJabberd::XMLElement->new($ns,'instructions',{},[$i]));
    }
    foreach my$v(@{$self->{order}}) {
	my $attr = { '{}var' => $v };
	$attr->{'{}type'} = $self->{fields}->{$v}->{type} if($self->{fields}->{$v}->{type});
	$attr->{'{}label'} = $self->{fields}->{$v}->{label} if($self->{fields}->{$v}->{label});
	my $kids = [];
	push(@{$kids},DJabberd::XMLElement->new($ns,'desc',{},[$self->{fields}->{$v}->{desc}])) if($self->{fields}->{$v}->{desc});
	push(@{$kids},DJabberd::XMLElement->new($ns,'required',{},[])) if($self->{fields}->{$v}->{required});
	foreach my$k(@{$self->{fields}->{$v}->{value}}) {
	    push(@{$kids},DJabberd::XMLElement->new($ns,'value',{},[$k]));
	}
	foreach my$k(@{$self->{fields}->{$v}->{option}}) {
	    my $oa = {};
	    $oa->{label} = $k->{label} if($k->{label});
	    push(@{$kids},DJabberd::XMLElement->new($ns,'option',$oa,[DJabberd::XMLElement->new('','value',{},[$k->{value}])]));
	}
	push(@innards,DJabberd::XMLElement->new($ns,'field',$attr,$kids));
    }
    return DJabberd::XMLElement->new($ns,'x',{xmlns=>$ns,($self->{type}?('{}type'=>$self->{type}):())},\@innards);
}
1;
