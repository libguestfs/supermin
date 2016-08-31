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

# The idea behind this test is that we have a list of tricky
# packages which are distro-specific, and try to install those
# and check they are installed correctly.

# NOTE:  This test will only work if the $pkgs listed below
# for your distro are installed on the host.  SEE LIST BELOW.

if [ -f /etc/os-release ]; then
    distro=$(. /etc/os-release && echo $ID)
    case "$distro" in
        fedora|rhel|centos) distro=redhat ;;
        opensuse|sled|sles) distro=suse ;;
        ubuntu) distro=debian ;;
    esac
elif [ -f /etc/arch-release ]; then
    distro=arch
elif [ -f /etc/debian_version ]; then
    distro=debian
elif [ -f /etc/redhat-release ]; then
    distro=redhat
elif [ -f /etc/SuSE-release ]; then
    distro=suse
elif [ -f /etc/ibm_powerkvm-release ]; then
    distro=ibm-powerkvm
else
    exit 77
fi

tmpdir=`mktemp -d`

d1=$tmpdir/d1
d2=$tmpdir/d2

case $distro in
    arch)
	# Choose at least one from AUR.
	pkgs="hivex"
	;;
    debian)
	pkgs="augeas-tools libaugeas0 libhivex0 libhivex-bin"
	;;
    redhat)
        # Choose tar because it has an epoch > 0 and is commonly
        # installed.  (See commit fb40baade8e3441b73ce6fd10a32fbbfe49cc4da)
	pkgs="augeas hivex tar"
	;;
    suse)
	pkgs="augeas hivex tar"
	;;
    ibm-powerkvm)
	pkgs="augeas hivex tar"
	;;
    *)
	echo "Unhandled distro '$distro'"
	exit 77
	;;
esac

test "$USE_NETWORK" = 1 || USE_INSTALLED=--use-installed

../src/supermin -v --prepare $USE_INSTALLED $pkgs -o $d1

# Build a chroot.
../src/supermin -v --build -f chroot $d1 -o $d2

# Check the result in a distro-specific manner.
case $distro in
    arch)
	if [ ! -x $d2/usr/bin/hivexget ]; then
	    echo "$0: $distro: hivexget binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libhivex.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: hivex library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	;;
    debian)
	if [ ! -x $d2/usr/bin/augtool ]; then
	    echo "$0: $distro: augtool binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libaugeas.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: augeas library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ ! -x $d2/usr/bin/hivexget ]; then
	    echo "$0: $distro: hivexget binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libhivex.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: hivex library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	;;
    redhat)
	if [ ! -x $d2/usr/bin/augtool ]; then
	    echo "$0: $distro: augtool binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libaugeas.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: augeas library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ ! -x $d2/usr/bin/hivexget ]; then
	    echo "$0: $distro: hivexget binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libhivex.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: hivex library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ ! -x $d2/bin/tar ]; then
	    echo "$0: $distro: tar binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	;;
    suse)
	if [ ! -x $d2/usr/bin/augtool ]; then
	    echo "$0: $distro: augtool binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libaugeas.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: augeas library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ ! -x $d2/usr/bin/hivexget ]; then
	    echo "$0: $distro: hivexget binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libhivex.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: hivex library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ ! -x $d2/bin/tar ]; then
	    echo "$0: $distro: tar binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	;;
    ibm-powerkvm)
	if [ ! -x $d2/usr/bin/augtool ]; then
	    echo "$0: $distro: augtool binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libaugeas.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: augeas library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ ! -x $d2/usr/bin/hivexget ]; then
	    echo "$0: $distro: hivexget binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ "$(find $d2/usr/lib* -name libhivex.so.0 | wc -l)" -lt 1 ]; then
	    echo "$0: $distro: hivex library not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	if [ ! -x $d2/bin/tar ]; then
	    echo "$0: $distro: tar binary not installed in chroot"
	    ls -lR $d2
	    exit 1
	fi
	;;
esac

# Need to chmod $d2 since rm -r can't remove unwritable directories.
chmod -R +w $d2 ||:
rm -rf $tmpdir
