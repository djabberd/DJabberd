#!/usr/bin/perl

use strict;
use Test::More tests => 5;
use lib 't/lib';
BEGIN { $ENV{LOGLEVEL} ||= "OFF" };
BEGIN { require 'djabberd-test.pl' }

use_ok("DJabberd::Plugin::SubdomainAlias");

$Test::DJabberd::Server::PLUGIN_CB = sub {
    my $self = shift;
    my $plugins = $self->standard_plugins();
    push @$plugins, DJabberd::Plugin::SubdomainAlias->new(subdomain => 'fooo');
    push @$plugins, DJabberd::Plugin::SubdomainAlias->new(subdomain => 'fooo');
    push @$plugins, DJabberd::Delivery::Local->new, DJabberd::Delivery::S2S->new; # these don't get pushed if someone else touches deliver
    return $plugins;
};

eval {
    two_parties_one_server(sub {
        my ($pa, $pb) = @_;
    });
};
like($@, qr/ already has .fooo. registered by plugin .DJabberd::Plugin::SubdomainAlias./, "Cannot load same one twice");

$Test::DJabberd::Server::PLUGIN_CB = sub {
    my $self = shift;
    my $plugins = $self->standard_plugins();
    push @$plugins, DJabberd::Plugin::SubdomainAlias->new(subdomain => 'fooo');
    push @$plugins, DJabberd::Delivery::Local->new, DJabberd::Delivery::S2S->new; # these don't get pushed if someone else touches deliver
    return $plugins;
};

two_parties_one_server(sub {
    my ($pa, $pb) = @_;
    $pa->login;
    $pb->login;

    # PA to PB
    $pa->send_xml("<message type='chat' to='$pb'>Hello.  I am $pa.</message>");
    like($pb->recv_xml, qr/type=.chat.*Hello.*I am \Q$pa\E/, "pb got pa's message");

    # PB to PA
    $pb->send_xml("<message type='chat' to='$pa'>Hello back!</message>");
    like($pa->recv_xml, qr/Hello back/, "pa got pb's message");
    pass("Plugin instaniated correctly");
});



