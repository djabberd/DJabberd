# object represents the open XML element for a stream
package DJabberd::StreamStart;
use strict;
use DJabberd::StreamVersion;

sub new {
    my ($class, $saxdata) = @_;
    return bless {
        saxdata => $saxdata,
    }, $class;
}

sub version {
    my $self = shift;
    return $self->{version} if $self->{version};

    my $ver;
    my $version_attr = $self->{saxdata}{Attributes}{"{}version"};
    if ($version_attr) {
        $ver = DJabberd::StreamVersion->new($version_attr->{Value});
    } else {
        $ver = DJabberd::StreamVersion->none;
    }

    return $self->{version} = $ver;
}

1;
