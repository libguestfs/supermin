#!/bin/bash -
# febootstrap-run
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
        -o g:i: \
        --long help,ro \
        -n febootstrap-run -- "$@"`
if [ $? != 0 ]; then
    echo "febootstrap-run: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

readonly=no

usage ()
{
    echo "Usage: febootstrap-run [--options] DIR [CMD]"
    echo "Please read febootstrap-run(8) man page for more information."
}

while true; do
    case "$1" in
	--ro)
	    readonly=yes
	    shift;;
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

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

target="$1"
shift

if [ ! -f "$target"/fakeroot.log ]; then
    echo "febootstrap-run: $target: not a root filesystem"
    exit 1
fi

if [ "$readonly" = "no" ]; then
    fakeroot -i "$target"/fakeroot.log -s "$target"/fakeroot.log \
	fakechroot -s \
	chroot "$target" "$@"
else
    fakeroot -i "$target"/fakeroot.log \
	fakechroot -s \
	chroot "$target" "$@"
fi
