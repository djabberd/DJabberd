package DJabberd::Util;
use strict;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(exml tsub lbsub as_bool as_num as_abs_path);

sub as_bool {
    my $val = shift;
    return 1 if $val =~ /^1|y|yes|true|t|on|enabled?$/i;
    return 0 if $val =~ /^0|n|no|false|f|off|disabled?$/i;
    die "Can't determine booleanness of '$val'\n";
}

sub as_num {
    my $val = shift;
    return $val if $val =~ /^\d+$/;
    die "Not a number\n";
}

sub as_abs_path {
    my $val = shift;
    die "Path isn't absolute" unless $val =~ m!^/!;
    die "File doesn't exist" unless -f $val;
    return $val;
}

sub exml
{
    # fast path for the commmon case:
    return $_[0] unless $_[0] =~ /[&\"\'<>\x00-\x08\x0B\x0C\x0E-\x1F]/;
    # what are those character ranges? XML 1.0 allows:
    # #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]

    my $a = shift;
    $a =~ s/\&/&amp;/g;
    $a =~ s/\"/&quot;/g;
    $a =~ s/\'/&apos;/g;
    $a =~ s/</&lt;/g;
    $a =~ s/>/&gt;/g;
    $a =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
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
    warn "blessing into $bpkg\n";
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
