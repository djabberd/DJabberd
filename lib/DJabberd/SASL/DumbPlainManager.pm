package DJabberd::SASL::DumbPlainManager;

use strict;
use warnings;

sub new {
    my $class = shift;
    my $plugin = shift;
    return bless { __plugin => $plugin }, $class;
}

sub server_start {
    my $self  = shift;
    my $creds = shift;
    my $plugin = $self->{__plugin};
    (undef, my $u, my $p) = split "\0", $creds, 3;
    if ($u eq $plugin->{user} && $p eq $plugin->{pass}) {
        $self->{success} = 1;
        return;
    }
    $self->{error} = "no match";
    return;
}

sub need_step   { }
sub server_step { } 
sub mechanism   { }
sub server_new  { $_[0]                   }
sub is_success  { $_[0]->{success}        }
sub error       { $_[0]->{error}          }
sub answer      { $_[0]->{__plugin}{user} }

sub     authenticated_jid { $_[0]->{jid}         } 
sub set_authenticated_jid { $_[0]->{jid} = $_[1] }

sub is_mechanism_supported { "dumb!" }

1;
