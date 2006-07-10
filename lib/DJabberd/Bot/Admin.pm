package DJabberd::Bot::Admin;
use strict;
use warnings;
use base 'DJabberd::Bot';
use DJabberd::Util qw(exml);
use List::Util qw(first);

our $logger = DJabberd::Log->get_logger();

sub finalize {
    my ($self) = @_;
    $self->{nodename} ||= "admin";
    $self->SUPER::finalize();
}

sub set_config_users {
    my ($self, $users) = @_;
    my @users = split /\s+/, $users;
    $self->{users}->{$_}++ foreach @users;
}

sub process_text {
    my ($self, $text, $from, $ctx) = @_;

    # access control:
    return if $self->{users} && !$self->{users}->{$from->node};

    warn "doing process for text: $text\n";

    $self->{buffer} = "";
    eval {
        DJabberd::Connection::Admin::process_line($self, $text);
    };
    if ($@) {
        $self->{buffer} = "Error: $@";
    }

    $ctx->reply($self->{buffer});
}

sub write {
    my ($self, $data) = @_;
    $self->{buffer} .= $data . "\n";
}

# specifically for being a connection::admin object:
sub end {
}

1;


