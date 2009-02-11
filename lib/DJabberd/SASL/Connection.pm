package DJabberd::SASL::Connection;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless { }, $class;
}

sub set_authenticated_jid {
    my $conn = shift;
    return $conn->{__authenticated_jid} = shift;
}

sub authenticated_jid {
    my $conn   = shift;
    return $conn->{__authenticated_jid};
}

1;

=pod

=head1 NAME

DJabberd::SASL::Connection - abstract base class for SASL connections

=head1 DESCRIPTION

An instance of this object is created by one SASL manager and attached to the
connection (L<DJabberd::Connection>) object when a SASL is being or has been
negotiated. Instances of that class (or subclasses) have the same interface
than L<Authen::SASL>'s connection object (server_start, server_step,
need_step, is_success, error...).

=head1 ADDITIONAL METHODS

=head2 authenticated_jid

A string representing the jid that is authenticated at the outcome of the
negotiation.

=head2 set_authenticated_jid($jid_string)

Sets the authenticated_jid

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
