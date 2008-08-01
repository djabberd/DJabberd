# -*-perl-*-

use strict;
use Test::More tests => 4;
BEGIN {
    $ENV{LOGLEVEL} = "WARN";
    use DJabberd::Log;
    DJabberd::Log->set_logger();
}
use DJabberd;
use DJabberd::Delivery::Local;
use Scalar::Util qw(weaken);


my $server = DJabberd->new;
my $local = DJabberd::Delivery::Local->new();
my $vhost = DJabberd::VHost->new(server_name => "foo");
$vhost->add_plugin($local);
$server->add_vhost($vhost);
DJabberd::HookDocs->allow_hook("Foo");
DJabberd::HookDocs->allow_hook("Nothing");

# scalar we used to hold weakrefs: if it goes undef, object was
# destroyed as desired.
my $track_obj;

# a variable to assign to from subrefs to assure there are side-effects
# that can't be optimized away
my $outside;

$vhost->register_hook("Foo", sub {
    my ($srv, $cb, @args) = @_;
    $cb->baz;
});

# testing an object in the args being destroyed
{
    my $obj = {};
    $track_obj = \$obj;
    weaken($track_obj);

    $vhost->run_hook_chain(phase   => "Foo",
                            args    => [ $obj, "arg2", "arg3" ],
                            methods => {
                                bar => sub {
                                    $outside = "bar!\n";
                                },
                                baz => sub {
                                    $outside = "baz!\n";
                                },
                            },
                            fallback => sub {
                                print "fallback.\n";
                            });
}
is($track_obj, undef, "ref in args destroyed");

# testing an object in the callbacks being destroyed
{
    my $obj = {};
    $track_obj = \$obj;
    weaken($track_obj);

    $vhost->run_hook_chain(phase   => "Foo",
                            args    => [ "arg1", "arg2" ],
                            methods => {
                                bar => sub {
                                    $outside = "bar $obj!\n";
                                },
                                baz => sub {
                                    $outside = "baz $obj!\n";
                                },
                            },
                            fallback => sub {
                                print "fallback.\n";
                            });
}
is($track_obj, undef, "ref in callbacks destroyed");

# testing an object in the fallback being destroyed
{
    my $obj = {};
    $track_obj = \$obj;
    weaken($track_obj);

    $vhost->run_hook_chain(phase   => "Foo",
                            args    => [ "arg1", "arg2" ],
                            methods => {
                                bar => sub {
                                    print "bar!\n";
                                },
                                baz => sub {
                                    $outside = "baz!\n";
                                },
                            },
                            fallback => sub {
                                $outside = "fallback $obj.\n";
                            });
}
is($track_obj, undef, "ref in fallback destroyed");

# testing an object in the fallback being destroyed, when we execute the fallback
{
    my $obj = {};
    $track_obj = \$obj;
    weaken($track_obj);

    $vhost->run_hook_chain(phase   => "Nothing",
                            args    => [ "arg1", "arg2" ],
                            methods => {
                                bar => sub {
                                    print "bar!\n";
                                },
                                baz => sub {
                                    $outside = "baz!\n";
                                },
                            },
                            fallback => sub {
                                $outside = "fallback $obj.\n";
                            });
}
is($track_obj, undef, "ref in executed fallback destroyed");

Danga::Socket->SetLoopTimeout(1000);
my $left = 2;
Danga::Socket->SetPostLoopCallback(sub {
    $left--;
    return 1 if $left > 0;
    return 0;
});
Danga::Socket->EventLoop();

1;
