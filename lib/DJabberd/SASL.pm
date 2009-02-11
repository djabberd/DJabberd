package DJabberd::SASL;
use strict;
use warnings;

use base qw/DJabberd::Plugin/;

use DJabberd::Stanza::SASL;
use DJabberd::SASL::Connection;
use DJabberd::Util qw(as_bool);

my $default = "DJabberd::SASL::Manager::AuthenSASL";
sub manager_class { $default }

my $sasl_ns = "urn:ietf:params:xml:ns:xmpp-sasl";
my %sasl_elements = (
    "{$sasl_ns}auth"      => 'DJabberd::Stanza::SASL',
    "{$sasl_ns}challenge" => 'DJabberd::Stanza::SASL',
    "{$sasl_ns}response"  => 'DJabberd::Stanza::SASL',
    "{$sasl_ns}abort"     => 'DJabberd::Stanza::SASL',
);

sub get_sasl_manager {
    my $self = shift;
    my $conn = shift;

    my $vhost = $conn->vhost
        or die "No VHost for this connection";

    my $class = $self->manager_class || $default;
    eval "use $class; 1;";
    die $@ if $@;
    return $class->new($self, $conn);
}

sub set_config_optional {
    my ($self, $val) = @_;
    $self->{optional} = as_bool($val);
}

sub is_optional { return $_->[0]->{optional} ? 1 : 0 }

sub mechanisms { die "implement" }

sub mechanisms_str {
    my $plugin = shift;
    return join " ", $plugin->mechanisms;
}

sub mechanisms_list {
    my $plugin = shift;
    return keys %{ $plugin->mechanisms };
}


## don't override, or be sure to call SUPER:: in the subclass
sub register {
    my ($plugin, $vhost) = @_;

    $vhost->register_hook("GetSASLManager", sub {
        my (undef, $cb, %args) = @_;
        my $conn = $args{conn};
        my $sasl = $plugin->get_sasl_manager($conn);
        $cb->get($sasl);
    });

    $vhost->register_hook("HandleStanza", sub {
        my (undef, $cb, $node) = @_;
        my $class = $sasl_elements{$node->element};
        return unless $class;
        $cb->handle($class);
        return;
    });
}

1;

__END__

=pod

=head1 NAME

DJabberd::SASL - Base plugin for SASL Negotiation 

=head1 DESCRIPTION

This base plugin just provides the skeleton necessary for building SASL layers
within DJabberd. It provides one hook (GetSASLManager) to initiate the SASL
negotiation and return a SASL Manager object; and it hooks the SASL stanzas
to the default L<DJabberd::Stanza::SASL> class.

See L<DJabberd::SASL::AuthenSASL> for a concrete plugin based on
I<DJabberd::SASL>.

=head1 HOW DOES THE DEFAULT SASL INFRASTRUCTURE WORK

When a I<DJabberd::SASL> subclass is declared inside of a B<VHost>, it enables
SASL negotiation for the connection.

What does that mean is that SASL will be advertised in the stream features.
Then, when the client sends a SASL stanza (see RFC 3920), they are handled
using L<DJabberd::Stanza::SASL> class, which makes a few assumption:

=over 4

=item * The plugin supports the I<GetSASLManager> hook that returns a 
L<DJabberd::SASL::ManagerBase> subclass.

=item * The interface to this manager and to the sasl connection
object (see later) is a superset of L<Authen::SASL> interface.

=back

From there, the SASL negotiation is in the hands of the configured SASL Manager.

One configuration option is common to all plugins: This is C<Optional> which 
advertises to the client if SASL is optional or not. By default SASL is (and
should be) required. 

=head1 SYNOPSIS

    <VHost yann.cyberion.net>
        <Plugin DJabberd::SASL::%Subclass%>
            Optional   yes
            %Config%
        </Plugin>
    </VHost>

=head1 EXTENDING SASL IN DJABBERD

See examples.

It's fairly easy to extend the SASL phase with anything you like provided the
simple L<DJabberd::SASL::ManagerBase> and L<DJabberd::SASL::Connection> which
are based on L<Authen::SASL> are repected.

Alternatively since this is just a plugin, you can also throw it away
altogether and write something from scratch. You'll have to provide a new set
of handlers for the SASL stanzas though (in replacement of
L<DJabberd::Stanzas::SASL>.

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
