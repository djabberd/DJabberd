
=head1 NAME

DJabberd::Delivery::LocalVHosts - Controlled delivery to other local VHosts

=head1 SYNOPSIS

<VHost mydomain.com>

  [...]

  <Plugin DJabberd::Delivery::LocalVHosts>
    AllowVHost component1.mydomain.com
    AllowVHost component2.mydomain.com
    ...
  </Plugin>

  [...]

</VHost>

This delivery plugin provides a shortcut for delivering messages between two
domains that are running on the same server. It also allows inter-VHost
communication on hosts that do not have S2S enabled at all, enabling admins
to create a closed pool of vhosts on one server that can only talk to one another,
if configuring S2S is impossible or inconvenient.

This plugin won't do anything at all unless you allow at least one vhost as
shown in the example above. By explicitly listing the appropriate services
you can create segregated pools of vhosts that can't communicate between
each other but can communicate within the configured bounds.

TODO: more docs

=cut

package DJabberd::Delivery::LocalVHosts;
use strict;
use warnings;
use base 'DJabberd::Delivery';
use DJabberd::Log;

our $logger = DJabberd::Log->get_logger;

sub set_config_allowvhost {
    my ($self, $hostname) = @_;
    $self->{allowed_vhosts} ||= {};
    $self->{allowed_vhosts}{$hostname} = 1;
}

sub finalize {
    my ($self) = @_;
    
    $logger->warn("You haven't allowed any vhosts for inter-vhost delivery.") unless $self->{allowed_vhosts};
    $self->{allowed_vhosts} ||= {};
}

sub run_before { ("DJabberd::Delivery::S2S") }

sub deliver {
    my ($self, $vhost, $cb, $stanza) = @_;

    my $server = $vhost->server;
    
    unless ($server) {
        return $cb->decline;
    }

    my $to = $stanza->to_jid or return $cb->decline;

    my $handler = $server->lookup_vhost($to->domain);
    
    unless ($handler) {
        $logger->debug("No local vhosts for ".$to->domain.".");
        return $cb->decline;
    }
    
    my $handler_name = $handler->server_name;
    
    # Sanity check: don't want to re-deliver to the same vhost
    if ($handler == $vhost) {
        return $cb->decline;
    }

    # Is it on the whitelist?
    unless ($self->{allowed_vhosts}{$handler_name}) {
        $logger->debug("Not delivering locally to $handler_name: not on allowed list.");
        return $cb->decline;
    }
    
    if ($handler) {
        $logger->debug($vhost->server_name." -> ".$handler->server_name);
        $stanza->deliver($handler);
        return $cb->delivered;
    }
    else {
        return $cb->decline;
    }
   
}

1;
