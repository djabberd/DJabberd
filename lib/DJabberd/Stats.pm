package DJabberd::Stats;
use strict;
use warnings;

# last 50,000 on_stanza_received latency numbers.  (from SAXHandler)
our $latency_max_size = 50_000;
our $latency_log_max_size = 10;
our $latency_index    = 0;
our $latency_log_index    = 0;
our @stanza_process_latency = ();
our @stanza_process_latency_log = ();
our $latency_log_threshold = 0.005;

our %counter = ();


1;
