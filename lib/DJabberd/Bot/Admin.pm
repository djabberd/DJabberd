
package DJabberd::Bot::Admin;
# abstract base class
use strict;
use warnings;
use base 'DJabberd::Bot';
use DJabberd::Util qw(exml);

our $logger = DJabberd::Log->get_logger();

sub initialize {
    my ($self, $opts) = @_;
    
    if (defined $opts->{users}) {
        my @users = split /\s+/, $opts->{users};
        $self->{users}->{$_}++ foreach @users;
    }
    
}

sub handle_message {
    my ($self, $stanza) = @_;

    my $body;
    foreach my $child ($stanza->children_elements) {
        if($child->{element} eq 'body') {
            $body = $child;
            last;
        }
    }
    $logger->logdie("Can't find a body in incoming message") unless $body;
    my $command = $body->first_child;

    my $from = $stanza->from_jid;
    my $to = $stanza->to_jid;

    return if ($self->{users} && !($self->{users}->{$from->node} && $from->domain eq $to->domain));

    my $can = DJabberd::Connection::Admin->can("CMD_$command");
    $self->{buffer} = "";

    if ($can) {
        $can->($self);
    } else {
        $self->{buffer} = "Unknown command '$command'";
    }

    return $self->{buffer};

}


sub write {
    my ($self, $data) = @_;
    $self->{buffer} .= $data . "\n";
}

sub end {

}

1;


