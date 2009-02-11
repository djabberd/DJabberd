#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 46;
use lib 't/lib';

require 'djabberd-test.pl';

use Authen::SASL 'Perl';

my $login_and_be = sub {
    my ($pa, $pb, $sasl, $res) = @_;

    my $jid = $pa->sasl_login($sasl, $res);
    $pb->login;
    $pa->send_xml("<presence/>");
    $pb->send_xml("<presence/>");

    $pa->send_xml("<iq type='get' id='pa1' to='$pb'><x/></iq>");
    like($pb->recv_xml, qr/id=.pa./, "pb got pa's iq");
    $pb->send_xml("<iq type='get' id='pb1' to='$pa'><x/></iq>");
    like($pa->recv_xml, qr/id=.pb./, "pb got pa's iq");
    return $jid;
};

## login successes
{
    for my $mechanism (qw/PLAIN LOGIN DIGEST-MD5/) {
        two_parties(sub {
            my ($pa, $pb) = @_;

            my $sasl = Authen::SASL->new(
                mechanism => $mechanism,
                callback  => {
                    pass => sub { $pa->password },
                    user => sub { $pa->{name}   },
                },
            );

            my $jid = $login_and_be->($pa, $pb, $sasl, "yann");
            is $jid->resource, 'yann', "resource assigned accordingly";
        });
    }
}

## resource not provided by the client 
{
    two_parties(sub {
        my ($pa, $pb) = @_;

        my $sasl = Authen::SASL->new(
            mechanism => "DIGEST-MD5",
            callback  => {
                pass => sub { $pa->password },
                user => sub { $pa->{name}   },
            },
        );

        my $jid = $login_and_be->($pa, $pb, $sasl, undef); # << no resource
        ok $jid, "got jid";
        ok $jid->resource, "assigned resource: " . $jid->resource;
    });
}

## resource conflict, resource reassigned
{
    two_parties(sub {
        my ($pa1, $pb) = @_;
        my $conflicted_res = "yann";

        my $pa2 = Test::DJabberd::Client->new(server   => $pa1->server,
                                              name     => $pa1->username,
                                              resource => $conflicted_res,
                                            );
        my $sasl = Authen::SASL->new(
            mechanism => "DIGEST-MD5",
            callback  => {
                pass => sub { $pa1->password },
                user => sub { $pa1->{name}   },
            },
        );
        my $pa1_res = $pa1->sasl_login($sasl, $conflicted_res)->resource;

        my $pa2_res = $pa2->sasl_login($sasl, $conflicted_res)->resource;
        cmp_ok $pa1_res, 'ne', $pa2_res, "resources are different";
        is   $pa1_res, $conflicted_res, "first got what it wanted";
        isnt $pa2_res, $conflicted_res, "second didn't";
    });
}

# a server available for tests using the common setup
my $server = Test::DJabberd::Server->new(id => 1);
$server->start;

## login failures
{
    for my $mechanism (qw/PLAIN LOGIN DIGEST-MD5/) {
        my $sasl = Authen::SASL->new(
            mechanism => $mechanism,
            callback  => {
                pass => "incorrect pass",
                user => "partya",
            },
        );

        my $pa = Test::DJabberd::Client->new(server => $server, name => "partya");
        eval { $pa->sasl_login($sasl, "yann") };
        my $err = $@;
        ok $err, "login failure";
        like $err, qr{failure.*<not-authorized/>};
    }
}

## abort
{
    my $sasl = Authen::SASL->new(
        mechanism => "DIGEST-MD5",
        callback  => {
            pass => "incorrect pass",
            user => "partya",
        },
    );

    my $pa = Test::DJabberd::Client->new(server => $server, name => "partya");
    my $response = $pa->abort_sasl_login($sasl, "yann");
    like $response, qr{failure.*<aborted/>};
}

## invalid mechanism
{
    my $strong_server = Test::DJabberd::Server->new( id => 2, );
    my $sasl_plugin =  DJabberd::SASL::AuthenSASL->new(
        mechanisms => "DIGEST-MD5", 
        optional   => "yes"
    );

    my $plugins = [ @{$strong_server->std_plugins_sans_sasl}, $sasl_plugin ];

    $strong_server->start($plugins);
    my $sasl = Authen::SASL->new(
        mechanism => "PLAIN",
        callback  => {
            pass => "incorrect pass",
            user => "partya",
        },
    );

    my $pa = Test::DJabberd::Client->new(server => $strong_server, name => "partya");
    eval { $pa->sasl_login($sasl, "yann") };
    my $err = $@;
    like $err, qr{failure.*<invalid-mechanism/>};
    $strong_server->kill;
}

## someone binding without authenticating
{
    my $pa = Test::DJabberd::Client->new(server => $server, name => "partya");
    $pa->connect or die "Failed to connect";
    my $sock = $pa->{sock};

    my $fail = sub {
        my $r = $pa->recv_xml;
        like $r, qr{<iq .* type='error'>.*</iq>}sm;
        like $r, qr{<error type='cancel'>.*</error>}sm;
        like $r, qr{<not-allowed xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>}sm;
    };

    print $sock "<iq id='bind_1' type='set'>
                    <bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/>
                </iq>";
    $fail->();

    print $sock '<auth xmlns="urn:ietf:params:xml:ns:xmpp-sasl" mechanism="DIGEST-MD5" />';
    $pa->recv_xml;
    print $sock "<iq id='bind_1' type='set'>
                    <bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/>
                </iq>";
    $fail->();
}

$server->kill;
