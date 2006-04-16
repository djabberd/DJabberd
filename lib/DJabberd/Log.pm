
package DJabberd::Log::Junk;

use Log::Log4perl qw();

package DJabberd::Log;
use strict;
use warnings;

no warnings 'redefine';
sub get_logger {
  my ($package, $filename, $line) = caller;
  return Log::Log4perl->get_logger($package);
}



our $has_run;
our $logger;
unless($has_run) {


  if(-e 'etc/djabberd.log') {
    Log::Log4perl->init_and_watch('etc/djabberd.log', 1);
    $logger = Log::Log4perl->get_logger();
  } else {
    Log::Log4perl->init_and_watch('etc/djabberd.log.default', 1);
    $logger = Log::Log4perl->get_logger();
    $logger->warn("Running with default log config file 'etc/djabberd.log.default', copy to 'etc/djabberd.log' to override");
  }
  $logger->info("Started logging");
  $has_run++;
}



1;
