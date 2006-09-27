use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
              'NAME'=> 'DJabberd',
              'VERSION' => '0.01',
              'PREREQ_PM'=> {
                             Danga::Socket                => 1.51,
                             XML::SAX                     => 0,
                             XML::LibXML::SAX             => 0,
                             Net::DNS                     => 0.48,
                             Net::SSLeay                  => 0,
                             Log::Log4perl                => 0,
                             Digest::HMAC_SHA1            => 0,
                            }, # e.g., Module::Name => 1.1
               AUTHOR     => 'Brad Fitzpatrick <brad@danga.com>',
             );
