#!/usr/bin/perl
# (C) Copyright 2009-2016 Hilko Bengen.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

# This script creates a C snippet embedding an arbitrary file
#
# The output provides two variables:
# static const char _binary_$name[];
# static const size_t _binary_$name_len;

use strict;
use warnings;

die "usage: $0 <in> <out>\n" if @ARGV != 2;

my ($infile, $outfile) = @ARGV;
my ($buf, $i, $sz);
open my $ifh, '<', $infile or die "open $infile: $!";
open my $ofh, '>', $outfile or die "open $outfile: $!";

my $infile_basename = $infile;
$infile_basename =~ s{.*/}{};

print $ofh <<"EOF";
/* This file has been automatically generated from $infile by $0 */

static const char _binary_${infile_basename}[] = {
EOF

$sz = 0;
while ( $i = read $ifh, $buf, 12 ) {
    print $ofh "  "
      . join( ", ", map { sprintf '0x%02x', ord $_ } split //, $buf ) . ",\n";
    $sz += $i;
}
die "read $infile (at offset $sz): $!\n" if not defined $i;
close $ifh;

print $ofh <<"EOF";
};
static const size_t _binary_${infile_basename}_len = ${sz};
EOF

close $ofh;
