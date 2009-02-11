#!/usr/bin/perl
use 5.008;
use ExtUtils::MakeMaker;
WriteMakefile(
              NAME         => 'DJabberd',
              VERSION_FROM => 'lib/DJabberd.pm',
              EXE_FILES    => ['djabberd'],
              ABSTRACT_FROM => 'lib/DJabberd.pm',
              PREREQ_PM    => {
                  'Danga::Socket'                => 1.51,
                  'XML::SAX'                     => 0,
                  'XML::LibXML::SAX'             => 0,
                  'Net::DNS'                     => 0.48,
                  'Net::SSLeay'                  => 0,
                  'Log::Log4perl'                => 0,
                  'Digest::HMAC_SHA1'            => 0,
              },
              clean      => { FILES => 't/log/*' },
              AUTHOR     => 'Brad Fitzpatrick <brad@danga.com>',
              );
