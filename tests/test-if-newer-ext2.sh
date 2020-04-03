#!/bin/bash -
# supermin
# (C) Copyright 2009-2020 Red Hat Inc.
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

set -e

# XXX Hack for Arch.
if [ -f /etc/arch-release ]; then
    export SUPERMIN_KERNEL=/boot/vmlinuz-linux
fi

tmpdir=`mktemp -d`

d1=$tmpdir/d1
d2=$tmpdir/d2

# We assume 'bash' is a package everywhere.
../src/supermin -v --prepare --use-installed bash -o $d1

run_supermin ()
{
  ../src/supermin -v --build -f ext2 --if-newer $d1 -o $d2
}

# Build the appliance the first time, which will work.
run_supermin

# No changes, hence nothing to do.
run_supermin | grep 'if-newer: output does not need rebuilding'

# Try removing any of the files, and check that supermin will detect that.
ext2_files="kernel initrd root"
for ext2_file in $ext2_files
do
  rm $d2/$ext2_file
  run_supermin
  for ext2_file in $ext2_files
  do
    test -e $d2/$ext2_file
  done
done

rm -rf $tmpdir ||:
