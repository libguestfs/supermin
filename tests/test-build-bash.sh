#!/bin/bash -
# supermin
# (C) Copyright 2009-2013 Red Hat Inc.
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

rm -f test-build-bash.{kernel,initrd,root}

d=test-build-bash.d
rm -rf $d
mkdir -p $d

# We assume 'bash' is a package everywhere.
../src/supermin -v --names bash -o $d

arch="$(uname -m)"

# Check all supermin-helper formats work.
../helper/supermin-helper -v -f checksum $d $arch
../helper/supermin-helper -v -f cpio $d $arch \
  test-build-bash.kernel test-build-bash.initrd
../helper/supermin-helper -v -f ext2 $d $arch \
  test-build-bash.kernel test-build-bash.initrd test-build-bash.root

rm -r $d
rm test-build-bash.{kernel,initrd,root}
