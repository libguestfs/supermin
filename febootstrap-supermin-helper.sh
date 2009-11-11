#!/bin/bash -
# febootstrap-supermin-helper
# (C) Copyright 2009 Red Hat Inc.
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
#
# Written by Richard W.M. Jones <rjones@redhat.com>

unset CDPATH

TEMP=`getopt \
        -o '' \
        --long help,kmods: \
        -n febootstrap-supermin-helper -- "$@"`
if [ $? != 0 ]; then
    echo "febootstrap-supermin-helper: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

usage ()
{
    echo "Usage: febootstrap-supermin-helper supermin.img hostfiles.txt kernel initrd"
    echo "Please read febootstrap-supermin-helper(8) man page for more information."
}

kmods=""

while true; do
    case "$1" in
	--help)
	    usage
	    exit 0;;
	--kmods)
	    kmods=$2
	    shift 2;;
	--)
	    shift
	    break;;
	*)
	    echo "Internal error!"
	    exit 1;;
    esac
done

if [ $# -ne 4 ]; then
    usage
    exit 1
fi

set -e

# Input files.
supermin="$1"
hostfiles="$2"

# Output files.
kernel="$3"
initrd="$4"

rm -f "$kernel" "$initrd"

# Kernel:
# Look for the most recent kernel named vmlinuz-*.<arch>* which has a
# corresponding directory in /lib/modules/. If the architecture is x86, look
# for any x86 kernel.
#
# RHEL 5 didn't append the arch to the kernel name, so look for kernels
# without arch second.

arch=$(echo "@host_cpu@" | sed 's/^i.86$/i?86/')
kernels=$(ls -1vr /boot/vmlinuz-*.$arch* 2>/dev/null | grep -v xen; ls -1vr /boot/vmlinuz-* 2>/dev/null | grep -v xen)
for f in $kernels; do
    b=$(basename "$f")
    b=$(echo "$b" | sed 's,vmlinuz-,,')
    modpath="/lib/modules/$b"
    if [ -d "$modpath" ]; then
        ln -sf "$f" "$kernel"
        break
    fi
    modpath=
done

if [ -z "$modpath" ]; then
    echo "$0: failed to find a suitable kernel" >&2
    exit 1
fi

# The initrd consists of these components:
# (1) The base skeleton appliance that we constructed at build time.
#     format = plain cpio (could be compressed cpio)
# (2) The modules from modpath which are on the module whitelist.
#     format = plain cpio
# (3) The host files which match wildcards in hostfiles.
#     format = plain cpio

cp "$supermin" "$initrd" ;# (1)

# Kernel modules (2).

if [ -n "$kmods" ]; then
    exec 5<"$kmods"
    whitelist=
    while read kmod 0<&5; do
	whitelist="$whitelist -o -name $kmod"
    done
    exec 5<&-
else
    whitelist="-o -name *.ko"
fi

find "$modpath" \( -not -name '*.ko' $whitelist \) -a -print0 |
  cpio --quiet -o -0 -H newc >> "$initrd"

# Host files (3).

hostfiles=$(readlink -f "$hostfiles")
(cd / &&
    ls -1df $(cat "$hostfiles") 2>/dev/null |
    cpio -C 65536 --quiet -o -H newc ) >> "$initrd"
