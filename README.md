This is the README file for DJabberd, a scalable, extensible Jabber/XMPP server.

Please refer to 'perldoc DJabberd' after installation for details.

## Description

DJabberd was the answer to LiveJournal's Jabber (XMPP) server needs.
We needed:

* good performance for tons of connected users
* ability to scale to multiple nodes
* ability to hook into LiveJournal at all places, not just auth

Basically we wanted the swiss army knife of Jabber servers (think
qpsmtpd or mod_perl), but none existed in any language.  While some
popular Jabber servers let us do pluggable auth, none let us get our
hands into roster storage, vcards, avatars, presence, etc.

So we made DJabberd.  It's a Jabber server where almost everything
defers to hooks to be implemented by plugins.  It does the core spec
itself (including SSL, StartTLS, server-to-server, etc), but it doesn't
come with any way to do authentication or storage or rosters, etc.
You'll need to go pick up a plugin to do those.

You should be able to plop DJabberd into your existing systems / user-
base with minimal pain.  Just find a plugin that's close (if a perfect
match doesn't already exist!) and tweak.
    
## Installation

DJabberd follows the standard perl module install process

perl Makefile.PL
make
make test
make install

The module uses no C or XS parts, so no c-compiler is required.

## Documentation

The documentation for DJabberd is somewhat lacking. Although 'perldoc
DJabberd' will give you the basics, and pointers for hackers, the best
way to get started is by delving into a demo application.

In the demo/ directory, you'll find a fully functional demo application,
which consists of:

  * A running server 
  * 2 pre-configured clients
  * An echo bot that is on all clients' roster

The demo application is heavily commented, and it's suggested you read
through the source code & comments to understand how it works.

Start by reading the demo/demo.conf file, and follow the classnames
from there.

To start the server, type the following commands from the same directory
as this README:

    perl -Ilib -Idemo/lib djabberd --conffile demo/demo.conf
  
You can now connect to it using the standard jabber ports on your localhost.
Read the demo/demo.conf file for additional notes.

For extra diagnostics from the server, you can increase the debuglevel
by setting the following environment variable:

    set LOGLEVEL=DEBUG

In the examples/ directory there's an example djabberd.conf
configuration file and the 'sixatalk' program.  'sixatalk' is an
example djabberd based server integrating with an LDAP directory.

