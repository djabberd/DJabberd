package DJabberd::SASL::ManagerBase;

use strict;
use warnings;

sub new {
    my $class  = shift;
    my $plugin = shift;
    my $self = bless {
        __sasl_plugin => $plugin,
    }, ref $class || $class;
    $self->{impl} = $self->manager_implementation(@_);
    return $self;
}

sub plugin {
    my $mgr = shift;
    return $mgr->{__sasl_plugin};
}
sub is_mechanism_supported { die "implement" }

sub DESTROY { }

sub AUTOLOAD {
    my $obj = shift;
    (my $meth = our $AUTOLOAD) =~ s/^.*:://;
    return $obj->{impl}->$meth(@_);
}

1;
__END__

=head1 NAME

DJabberd::SASL::ManagerBase - Abstract base clase for the main SASL object.

=head1 DESCRIPTION

The SASL Manager is the main object instantiated when a negotiation starts. It's
a wrapper around L<Authen::SASL>, plus some helpers.

=head1 INTERFACE

see L<Authen::SASL> and L<Authen::SASL::Perl> for the base methods.

=head2 plugin

returns the L<DJabberd::SASL> plugin responsible for instantiating this manager.

=head2 server_new

has the same interface, but returns a L<DJabberd::SASL::Connection> instance
instead of a regular SASL Mechanism handling class.

=head2 is_mechanism_supported($mechanism)

Subclasses should provide this method.

returns true or false depending if C<$mechanism> is supporte by the underlaying
implementation and the current configuration.

=head1 COPYRIGHT

(c) 2009 Yann Kerherve

This module is part of the DJabberd distribution and is covered by the
distribution's overall licence.

=cut

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:
