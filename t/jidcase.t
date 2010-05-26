use strict;
use warnings;

use lib "t/lib";
BEGIN { require 'djabberd-test.pl'; }

use DJabberd;
use DJabberd::JID;

my @tests;
BEGIN {
    @tests = qw(
        TEST@EXAMPLE.COM test@example.com
        test@example.com test@example.com
        TEsT@example.com test@example.com
        test@EXAMPLE.COM test@example.com
        test@example.com/Client test@example.com/Client
        test@example.com/CLIENT test@example.com/CLIENT
        example.com example.com
        EXAMpLe.CoM example.com
        example.com/resource example.com/resource
        example.com/ReSouRce example.com/ReSouRce
    );

    require 'Test/More.pm';
    Test::More->import(tests => scalar(@tests));

}

for (my $i = 0; $i < scalar(@tests); $i += 2) {
    my $input = $tests[$i];
    my $expected = $tests[$i+1];

    last unless defined($input);

    my $jid = DJabberd::JID->new($input);

    is($jid->as_string, $expected, $input." in standard mode");
}

# Now test our case-sensitive compatibility mode
$DJabberd::JID::CASE_SENSITIVE = 1;

for (my $i = 0; $i < scalar(@tests); $i += 2) {
    my $input = $tests[$i];
    my $expected = $tests[$i+1];

    last unless defined($input);

    my $jid = DJabberd::JID->new($input);

    is($jid->as_string, $input, $input." in case-sensitive compatibility mode");
}


