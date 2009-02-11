package DJabberd::SASL::Manager::AuthenSASL;

use strict;
use warnings;

use base qw/DJabberd::SASL::ManagerBase/;
use DJabberd::SASL::Connection::AuthenSASL;

use Authen::SASL ('Perl');

sub server_new {
    my $obj = shift;
    my $conn = $obj->{impl}->server_new(@_);
    return DJabberd::SASL::Connection::AuthenSASL->new($conn);
}

sub is_mechanism_supported {
    my $sasl      = shift;
    my $mechanism = shift;

    ## FIXME We might want to check that what's declared in the config
    ## is supported in Authen::SASL
    my $plugin = $sasl->{__sasl_plugin};
    return $plugin->mechanisms->{uc $mechanism};
    return 1;
}

sub manager_implementation {
    my $mgr  = shift;
    my $conn = shift;

    my $plugin = $mgr->plugin;
    my $vhost  = $conn->vhost or die "missing vhost";

    my $mechanisms = $plugin->mechanisms_str;
    my $saslmgr    = Authen::SASL->new(
        mechanism => $mechanisms,
        callback => {
            checkpass => sub {
                my $sasl = shift;
                my ($user, $pass, $realm) = @_;

                my $success;
                if ($vhost->are_hooks("CheckCleartext")) {
                    $vhost->run_hook_chain(phase => "CheckCleartext",
                            args  => [ username => $user, password => $pass ],
                            methods => {
                                accept => sub { $success = 1 },
                                reject => sub { $success = 0 },
                            },
                    );
                }
                return $success;
            },
            getsecret => sub {
                my $sasl = shift;
                my ($user, $authname) = @_;
                my $pass;

                if ($vhost->are_hooks("GetPassword")) {
                    $vhost->run_hook_chain(phase => "GetPassword",
                            args  => [ username => $user, ],
                            methods => {
                                set => sub {
                                    my (undef, $good_password) = @_;
                                    $pass = $good_password;
                                },
                            },
                    );
                }
                return $pass;
            },
        },
    );
    return $saslmgr;
}

1;
