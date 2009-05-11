#!/bin/bash -
# febootstrap-install
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

usage ()
{
    echo "Usage: febootstrap-install ROOT LOCALFILE TARGETPATH MODE OWNER[.GROUP]"
    echo "Please read febootstrap-install(8) man page for more information."
}

if [ $# != 5 ]; then
    usage
    exit 1
fi

set -e

# This is a carefully chosen sequence of commands which
# tries not to disturb any inode numbers apart from the
# one for the new file.
cp "$2" "$1"/"$3"
ino=$(ls -i "$1"/"$3" | awk '{print $1}')
cp "$1"/fakeroot.log "$1"/fakeroot.log.old
grep -v "ino=$ino," "$1"/fakeroot.log.old > "$1"/fakeroot.log
rm "$1"/fakeroot.log.old
febootstrap-run "$1" -- chmod "$4" "$3"
febootstrap-run "$1" -- chown "$5" "$3"
