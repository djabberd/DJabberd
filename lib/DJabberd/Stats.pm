package DJabberd::Stats;
use strict;
use warnings;
use Hash::Util qw(lock_keys);


our %counter = (
                 iq_get => 0,
                 iq_set => 0,
                 iq_result => 0,
                 connect => 0,
                 disconnect => 0,
                 local_deliver => 0,
                 s2s_deliver => 0,
                 );


lock_keys(%counter);
1;
