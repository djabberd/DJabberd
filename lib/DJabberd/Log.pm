
package DJabberd::Log::Junk;

use Log::Log4perl qw(:resurrect);

package DJabberd::Log;
use strict;
use warnings;

no warnings 'redefine';
sub get_logger {
    my ($class, $category) = @_;
    my ($package, $filename, $line) = caller;
    return Log::Log4perl->get_logger($category || $package);
}

our $has_run;
our $logger;
unless ($has_run) {

    my $used_file;
    my @locations = ("/etc/djabberd/log.conf",
                     "etc/djabberd.log",
                     "etc/djabberd.log.default");
    @locations = () if $ENV{LOGLEVEL};
    foreach my $conffile (@locations) {
        next unless -e $conffile;
        Log::Log4perl->init_and_watch($conffile, 1);
        $logger = Log::Log4perl->get_logger();
        $used_file = $conffile;
    }

    my $loglevel = $ENV{LOGLEVEL} || "WARN";

    unless ($used_file) {
        my $conf = qq{
log4perl.logger.DJabberd = $loglevel, screen
log4perl.logger.DJabberd.Hook = $loglevel

# This psuedo class is used to control if raw XML is to be showed or not
# at DEBUG it shows all raw traffic
# at INFO  it censors out the actual data
log4perl.logger.DJabberd.Connection.XML = $loglevel

log4perl.appender.screen = Log::Log4perl::Appender::ScreenColoredLevels
log4perl.appender.screen.layout = Log::Log4perl::Layout::PatternLayout
log4perl.appender.screen.layout.ConversionPattern = %P %-5p %-40c %m %n
};
        Log::Log4perl->init(\$conf);
        $logger = Log::Log4perl->get_logger();
        $used_file = "BUILT-IN-DEFAULTS";
    }

    $logger->info("Started logging using '$used_file'");
    $has_run++;
}

# Local Variables:
# mode: perl
# c-basic-indent: 4
# indent-tabs-mode: nil
# End:

1;
