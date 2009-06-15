#!/bin/bash -
# febootstrap-to-initramfs
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
        --long files:,help \
        -n febootstrap-to-initramfs -- "$@"`
if [ $? != 0 ]; then
    echo "febootstrap-to-initramfs: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

files=

usage ()
{
    echo "Usage: febootstrap-to-initramfs [--files=filelist] DIR"
    echo "Please read febootstrap-to-initramfs(8) man page for more information."
}

while true; do
    case "$1" in
	--files)
	    files=$2
	    shift 2;;
	--help)
	    usage
	    exit 0;;
	--)
	    shift
	    break;;
	*)
	    echo "Internal error!"
	    exit 1;;
    esac
done

if [ $# -ne 1 ]; then
    usage
    exit 1
fi

cd "$1" > /dev/null

if [ ! -f fakeroot.log -a $(id -u) -ne 0 ]; then
    echo "no fakeroot.log and not running as root"
    exit 1
fi

set -e

if [ -f fakeroot.log ]; then
    if [ -z "$files" ]; then
	fakeroot -i fakeroot.log \
	sh -c 'find -not -name fakeroot.log -a -print0 | cpio -o -0 -H newc | gzip --best'
    else
	fakeroot -i fakeroot.log \
	sh -c 'cpio -o -H newc | gzip --best' < $files
    fi
else
    if [ -z "$files" ]; then
	find -not -name fakeroot.log -a -print0 | cpio -o -0 -H newc | gzip --best
    else
	cpio -o -H newc < $files | gzip --best
    fi
fi
