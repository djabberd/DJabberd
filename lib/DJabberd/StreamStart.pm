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

sub announced_dialback {
    my $self = shift;
    my $attr = $self->{saxdata}{Attributes}{"{http://www.w3.org/2000/xmlns/}db"};
    return $attr && $attr->{Value} eq "jabber:server:dialback";
}

sub to {
    my $self = shift;
    my $to_attr = $self->{saxdata}{Attributes}{"{}to"} or
        return "";
    return $to_attr->{Value};
}

sub id {
    my $self = shift;
    my $attr = $self->{saxdata}{Attributes}{"{}id"} or
        return "";
    return $attr->{Value};
}

1;
