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

tmpdir=`mktemp -d`

d1=$tmpdir/d1
d2=$tmpdir/d2

test "$USE_NETWORK" = 1 || USE_INSTALLED=--use-installed

# We assume that 'bash' and 'coreutils' package names exist in every distro.
../src/supermin -v --prepare $USE_INSTALLED bash coreutils -o $d1

# Build a chroot.
../src/supermin -v --build -f chroot $d1 -o $d2

# Check that some well-known binaries were created.
if [ "$(find $d2 -name bash | wc -l)" -lt 1 ]; then
    echo "$0: 'bash' binary was not created in chroot"
    ls -lR $d2
    exit 1
fi
if [ "$(find $d2 -name sync | wc -l)" -lt 1 ]; then
    echo "$0: 'sync' binary was not created in chroot"
    ls -lR $d2
    exit 1
fi

# Check the mode of the binaries.
if [ "$(find $d2 -name bash -perm -0555 | wc -l)" -lt 1 ]; then
    echo "$0: 'bash' binary was not created with the right mode"
    ls -lR $d2
    exit 1
fi
if [ "$(find $d2 -name sync -perm -0555 | wc -l)" -lt 1 ]; then
    echo "$0: 'sync' binary was not created with the right mode"
    ls -lR $d2
    exit 1
fi

# These binaries should be runnable (since they are the same as the host).
`find $d2 -name sync | head`

rm -rf $tmpdir ||:
