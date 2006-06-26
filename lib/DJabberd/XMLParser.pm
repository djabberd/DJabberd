package DJabberd::XMLParser;
use strict;
use vars qw($VERSION @ISA);
$VERSION = '1.00';
use XML::LibXML;
use XML::SAX::Base;
use base qw(XML::SAX::Base);
use Carp;
use Scalar::Util ();

our $instance_count = 0;

sub new {
    my ($class, @params) = @_;
    my $self = $class->SUPER::new(@params);

    # libxml mode:
    if (1) {
        my $libxml = XML::LibXML->new;
        $libxml->set_handler($self);
        $self->{LibParser} = $libxml;
        Scalar::Util::weaken($self->{LibParser});

        $libxml->init_push;
        $self->{CONTEXT} = $libxml->{CONTEXT};
    }

    # expat mode:
    if (0) {
        #use XML::SAX::Expat::Incremental;
        my $parser = XML::SAX::Expat::Incremental->new(Handler => $self);
        $self->{expat} = $parser;
        $parser->parse_start;
    }

    $instance_count++;
    return $self;
}

*parse_more = \&parse_chunk;
sub parse_chunk {
    #my ($self, $chunk) = @_;

    # 'push' (wrapper around _push) without context also works,
    # but _push (xs) is enough faster...
    $_[0]->{LibParser}->_push($_[0]->{CONTEXT},
                              $_[1]);

    # expat version:
    # $_[0]->{expat}->parse_more($_[1]);
}

sub parse_chunk_scalarref {
    #my ($self, $chunk) = @_;

    # 'push' (wrapper around _push) without context also works,
    # but _push (xs) is enough faster...
    $_[0]->{LibParser}->_push($_[0]->{CONTEXT},
                              ${$_[1]});

    # expat version:
    # $_[0]->{expat}->parse_more(${$_[1]});
}

sub finish_push {
    my $self = shift;
    return 1 unless $self->{LibParser};
    my $parser = delete $self->{LibParser};
    eval { $parser->finish_push };
    delete $self->{Handler};
    delete $self->{CONTEXT};
    return 1;
}

sub DESTROY {
    my $self = shift;
    $instance_count--;
    bless $self, 'XML::SAX::Base';
}
