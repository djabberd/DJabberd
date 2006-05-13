package DJabberd::XMLParser;
use strict;
use vars qw($VERSION @ISA);
$VERSION = '1.00';
use XML::LibXML;
use XML::SAX::Base;
use base qw(XML::SAX::Base);
use Carp;

sub new {
    my ($class, @params) = @_;
    my $self = $class->SUPER::new(@params);

    my $libxml = XML::LibXML->new;
    $libxml->set_handler($self);
    $self->{LibParser} = $libxml;
    $libxml->init_push;

    return $self;
}

*parse_more = \&parse_chunk;
sub parse_chunk {
    #my ($self, $chunk) = @_;
    $_[0]->{LibParser}->push($_[1]);
}

sub parse_chunk_scalarref {
    #my ($self, $chunk) = @_;
    $_[0]->{LibParser}->push(${$_[1]});
}

sub finish_push {
    my $self = shift;
    return 1 unless $self->{LibParser};
    my $parser = delete $self->{LibParser};
    eval { $parser->finish_push };
    return 1;
}
