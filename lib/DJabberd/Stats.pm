package DJabberd::Stats;
use strict;
use warnings;

# last 50,000 on_stanza_received latency numbers.  (from SAXHandler)
our $latency_max_size = 50_000;
our $latency_index    = 0;
our @stanza_process_latency = ();

our %counter = (
                 iq_get => 0,
                 iq_set => 0,
                 iq_result => 0,
                 connect => 0,
                 disconnect => 0,
                 local_deliver => 0,
                 s2s_deliver => 0,
                 );

1;
