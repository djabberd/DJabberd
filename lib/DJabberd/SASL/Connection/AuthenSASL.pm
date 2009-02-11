package DJabberd::SASL::Connection::AuthenSASL;
use strict;
use warnings;
use base 'DJabberd::SASL::Connection';

sub new {
    my $class = shift;
    my $sasl_conn  = shift;
    return bless { impl => $sasl_conn }, ref $class || $class;
}

sub DESTROY { }

sub AUTOLOAD {
    my $obj = shift;
    (my $meth = our $AUTOLOAD) =~ s/^.*:://;
    return $obj->{impl}->$meth(@_);
}

1;
