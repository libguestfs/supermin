#!/usr/bin/perl

# This script creates a source file for the GNU assembler which shuold
# result in an object file equivalent to that of
#
# objcopy -I binary -B $(DEFAULT_ARCH) -O $(ELF_DEFAULT_ARCH) <in> <out>

use strict;
use warnings;

die "usage: $0 <in> <out>\n" if @ARGV != 2;

my ($infile, $outfile) = @ARGV;
my ($buf, $i, $sz);
open my $ifh, '<', $infile or die "open $infile: $!";
open my $ofh, '>', $outfile or die "open $outfile: $!";

print $ofh <<"EOF";
/* This file has been automatically generated from $infile by $0 */

\t.globl\t_binary_${infile}_start
\t.globl\t_binary_${infile}_end
\t.globl\t_binary_${infile}_size

\t.section\t.data
_binary_${infile}_start:
EOF

$sz = 0;
while ( $i = read $ifh, $buf, 12 ) {
    print $ofh "\t.byte\t"
      . join( ',', map { sprintf '0x%02x', ord $_ } split //, $buf ) . "\n";
    $sz += $i;
}
die "read $infile (at offset $sz): $!\n" if not defined $i;
close $ifh;

print $ofh <<"EOF";

_binary_${infile}_end:

\t.equ _binary_${infile}_size, $sz
EOF

close $ofh;
