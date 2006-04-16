# -*-perl-*-

use strict;
use Test::More 'no_plan';
use DJabberd;
use Scalar::Util qw(weaken);

my $server = DJabberd->new;
DJabberd::HookDocs->allow_hook("Foo");

$server->register_hook("Foo", sub {
    my ($srv, $cb, @args) = @_;
    $cb->baz;
});

my $track_obj;
{
    my $obj = {};
    $track_obj = \$obj;
    weaken($track_obj);
    isnt($track_obj, undef, "\$obj has a value");

    $server->run_hook_chain(phase   => "Foo",
                            args    => [ $obj, "arg1", "arg2" ],
                            methods => {
                                bar => sub {
                                    print "bar!\n";
                                },
                                baz => sub {
                                    print "baz!\n";
                                },
                            },
                            fallback => sub {
                                print "fallback.\n";
                            });
}

# make sure that $obj above went out of scope
is($track_obj, undef, "\$obj was destroyed");

Danga::Socket->SetLoopTimeout(1000);
my $left = 2;
Danga::Socket->SetPostLoopCallback(sub {
    $left--;
    return 1 if $left > 0;
    return 0;
});
Danga::Socket->EventLoop();

1;
