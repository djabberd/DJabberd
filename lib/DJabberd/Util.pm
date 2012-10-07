package DJabberd::Util;
use strict;
use HTML::Entities qw();
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(exml tsub lbsub as_bool as_num as_abs_path as_bind_addr);

sub as_bool {
    my $val = shift;
    die "Can't determine booleanness of 'undef'\n" unless defined($val);
    return 1 if $val =~ /^1|y|yes|true|t|on|enabled?$/i;
    return 0 if $val =~ /^0|n|no|false|f|off|disabled?$/i;
    die "Can't determine booleanness of '$val'\n";
}

sub as_num {
    my $val = shift;
    return $val if $val =~ /^\d+$/;
    die "'$val' is not a number\n";
}

sub as_bind_addr {
    my $val = shift;
    die "'undef' is not a valid bind address or port\n" unless defined($val);
    # Must either be like 127.0.0.1:1234, a bare port number or an absolute path to a unix domain socket
    # a socket
    if ($val && $val =~ m!^/! && -e $val) {
        return $val;
    }
    # an port, possibly including an IPv4 address
    if ($val && $val =~ /^(?:\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?:)?(\d+)$/) {
        if($1 > 0 && $1 <= 65535) {
            return $val;
        }
    }
    # looks like an IPv6 address
    if ($val && $val =~ /^\[[0-9a-f:]+\]:(\d+)$/) {
        if($1 > 0 && $1 <= 65535) {
            return $val;
        }
    }
    die "'$val' is not a valid bind address or port\n";
}

sub as_abs_path {
    my $val = shift;
    die "Path '$val' isn't absolute" unless $val =~ m!^/!;
    die "File '$val' doesn't exist" unless -f $val;
    return $val;
}

sub exml
{
    return HTML::Entities::encode_entities_numeric(shift);
}

sub durl {
    my ($a) = @_;
    $a =~ tr/+/ /;
    $a =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
    return $a;
}

# tracked sub
sub tsub (&) {
    my $subref = shift;
    bless $subref, 'DJabberd::TrackedSub';
    DJabberd->track_new_obj($subref);
    return $subref;
}

# line-blessed sub
sub lbsub (&) {
    my $subref = shift;
    my ($pkg, $file, $line) = caller;
    my $bpkg = $file . "_" . $line;
    $bpkg =~ s/[^\w]/_/g;
    return bless $subref, "DJabberd::AnonSubFrom::$bpkg";
}

sub numeric_entity_clean {
    my $hex = $_[0];
    my $val = hex $hex;

    # under a space, only \n, \r, and \t are allowed.
    if ($val < 32 && ($val != 13 && $val != 10 && $val != 9)) {
        return "";
    }

    return "&#$hex;";
}

package DJabberd::TrackedSub;

sub DESTROY {
    my $self = shift;
    DJabberd->track_destroyed_obj($self);
}

1;
