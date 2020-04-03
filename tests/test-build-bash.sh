#!/bin/bash -
# supermin
# (C) Copyright 2009-2014 Red Hat Inc.
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
d3=$tmpdir/d3

test "$USE_NETWORK" = 1 || USE_INSTALLED=--use-installed

# We assume 'bash' is a package everywhere.
../src/supermin -v --prepare $USE_INSTALLED bash -o $d1

arch="$(uname -m)"

# Check all supermin-helper formats work.
../src/supermin -v --build -f chroot --host-cpu $arch $d1 -o $d2
../src/supermin -v --build -f ext2 --host-cpu $arch $d1 -o $d3

# Need to chmod $d2 since rm -r can't remove unwritable directories.
chmod -R +w $d2 ||:
rm -rf $tmpdir ||:
