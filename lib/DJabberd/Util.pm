package DJabberd::Util;
use strict;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(exml tsub as_bool as_num);

sub as_bool {
    my $val = shift;
    return 1 if $val =~ /^1|yes|true|t|on|enabled?$/;
    return 0 if $val =~ /^0|no|false|f|off|disabled?$/;
    die "Can't determine booleanness of '$val'\n";
}

sub as_num {
    my $val = shift;
    return $val if $val =~ /^\d+$/;
    die "Not a number\n";
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

sub tsub (&) {
    my $subref = shift;
    bless $subref, 'DJabberd::TrackedSub';
    DJabberd->track_new_obj($subref);
    return $subref;
}

package DJabberd::TrackedSub;

sub DESTROY {
    my $self = shift;
    DJabberd->track_destroyed_obj($self);
}

1;
