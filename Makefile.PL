use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      'NAME'=> 'DJabberd',
	      'VERSION' => '0.01',
	      'PREREQ_PM'=> {
			     Danga::Socket                => 1.49,
			     XML::SAX                     => 0,
			     XML::SAX::Expat::Incremental => 0,
			     Net::DNS                     => 0.57,
			     Net::SSLeay                  => 0,
			     DBI                          => 0,
			     LWP::Simple                  => 0,
			     DBD::SQLite                  => 0,
			    }, # e.g., Module::Name => 1.1
	       AUTHOR     => 'Brad Fitzpatrick <brad@danga.com>',
	     );
