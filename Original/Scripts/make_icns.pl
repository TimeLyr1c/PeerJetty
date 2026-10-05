use strict;
use warnings;

my ($output, @specifications) = @ARGV;
die "usage: make_icns.pl output.icns type=image.png ...\n" unless $output && @specifications;

my $body = "";
for my $specification (@specifications) {
    my ($type, $path) = split(/=/, $specification, 2);
    die "invalid icon specification: $specification\n" unless $type && $path && length($type) == 4;

    open my $input, "<", $path or die "cannot open $path: $!\n";
    binmode $input;
    local $/;
    my $data = <$input>;
    close $input;

    $body .= $type . pack("N", length($data) + 8) . $data;
}

open my $icon, ">", $output or die "cannot write $output: $!\n";
binmode $icon;
print {$icon} "icns", pack("N", length($body) + 8), $body;
close $icon;
