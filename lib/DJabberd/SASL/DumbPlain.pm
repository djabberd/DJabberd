package DJabberd::SASL::DumbPlain;

use strict;
use warnings;
use base qw/DJabberd::SASL/;

sub manager_class { 'DJabberd::SASL::DumbPlainManager' }
sub mechanisms {
    my $plugin = shift;
    return { PLAIN => 1 };
}

sub set_config_user {
    my ($self, $val) = @_;
    $val =~ s/^\s*\b(.+)\b\s*$/$1/;
    $self->{user} = $val;
}

sub set_config_pass {
    my ($self, $val) = @_;
    $val =~ s/^\s*\b(.+)\b\s*$/$1/;
    $self->{pass} = $val;
}

## XXX dupe sux
sub register {
    my ($plugin, $vhost) = @_;
    $plugin->SUPER::register($vhost);

    $vhost->register_hook("SendFeatures", sub {
        my ($vh, $cb, $conn) = @_;
        if (my $sasl_conn = $conn->sasl) {
            if ($sasl_conn->is_success) {
                return;
            }
        }
        my @mech = $plugin->mechanisms_list;
        my $xml_mechanisms =
            "<mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>";
        $xml_mechanisms .= join "", map { "<mechanism>$_</mechanism>" } @mech;
        $xml_mechanisms .= "<optional/>" if $plugin->is_optional;
        $xml_mechanisms .= "</mechanisms>";
        $cb->stanza($xml_mechanisms);
    });
}

1;
__END__

=head1 NAME

DJabberd::SASL::DumbPlain - Dumb Plain SASL Auth plugin 

=head1 SYNOPSIS

    <Plugin DJabberd::SASL::DumbPlain>
        Optional   yes
        User       yann
        Pass       secret
    </Plugin>

=head1 DESCRIPTION

Dumb demo/test module.

=cut

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:
