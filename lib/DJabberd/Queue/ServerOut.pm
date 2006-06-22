package DJabberd::Queue::ServerOut;
use strict;
use warnings;

use base 'DJabberd::Queue';
use DJabberd::Queue qw(NO_CONN RESOLVING);
use fields (
	    'domain',
	    'del_source',
	    );

use DJabberd::Connection::ServerOut;

use DJabberd::Log;

our $logger = DJabberd::Log->get_logger;

sub new {
    my ($class, %opts) = @_;

#    warn( join ",", keys %opts );
#    warn( $opts{domain});
				  
    my $domain = delete $opts{domain}
        or Carp::confess "domain required";
    my $del_source = delete $opts{source}
        or die "delivery 'source' required";
    my $self = fields::new($class);
    $self->SUPER::new( %opts );

    $self->{domain} = $domain;
    $self->{del_source} = $del_source;

    return $self;
}

sub domain {
    my $self = shift;
    return $self->{domain};
}

sub queue_stanza {
    my $self = shift;
    # Passthrough, maybe we should warn and depricate?
    return $self->SUPER::enqueue( @_ );
}

sub start_connecting {
    my $self = shift;
    $logger->debug("Starting connection to domain '$self->{domain}'");
    die unless $self->{state} == NO_CONN;

    # TODO: moratorium/exponential backoff on attempting to deliver to
    # something that's recently failed to connect.  instead, immediately
    # call ->failed_to_connect without even trying.

    $self->{state} = RESOLVING;

    # async DNS lookup
    DJabberd::DNS->srv(service  => "_xmpp-server._tcp",
                       domain   => $self->{domain},
                       callback => sub {
                           $self->endpoints(@_);
                           $logger->debug("Resolver callback for '$self->{domain}': [@_]");
			   $self->{state} = NO_CONN;
			   $self->SUPER::start_connecting;
                       });
}

sub new_connection {
    my $self = shift;
    my %opts = @_;

    return DJabberd::Connection::ServerOut->new(%opts);
}

1;
