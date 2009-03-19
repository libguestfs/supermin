#!/bin/bash -
# febootstrap
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

TEMP=`getopt \
        -o g:i: \
        --long groupinstall:,group-install:,help,install: \
        -n febootstrap -- "$@"`
if [ $? != 0 ]; then
    echo "febootstrap: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

declare -a packages
packages[0]="@Core"
i=0

usage ()
{
    echo "Usage: febootstrap [--options] REPO TARGET [MIRROR]"
    echo "Please read febootstrap(8) man page for more information."
}

while true; do
    case "$1" in
	-i|--install)
	    packages[i++]="$2"
	    shift 2;;
	--groupinstall|--group-install)
	    packages[i++]="@$2"
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

if [ $# -lt 2 -o $# -gt 3 ]; then
    usage
    exit 1
fi

repo="$1"
target="$2"
mirror="$3"

# Architecture is currently always the same as the current arch.  We
# cannot do --foreign builds.  See discussion in the manpage.
arch=$(arch)

# Create a temporary directory, make sure it gets cleaned up at the end.
tmpdir=$(mktemp -d)
remove_tmpdir ()
{
  status=$?
  rm -rf "$tmpdir" && exit $status
}
trap remove_tmpdir EXIT

# Create the temporary repository configuration.  The name of the
# repository is always 'febootstrap'.
cat > $tmpdir/febootstrap.repo <<__EOF__
[febootstrap]
name=febootstrap $repo $arch
failovermethod=priority
enabled=1
gpgcheck=0
__EOF__

# "Mirror" parameter is a bit misnamed, but it means a local mirror,
# instead of the public Fedora mirrors.
if [ -n "$mirror" ]; then
    echo "baseurl=$mirror" >> "$tmpdir"/febootstrap.repo
else
    echo "mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=$repo&arch=$arch" >> "$tmpdir"/febootstrap.repo
fi

# Create the target filesystem.
rm -rf "$target"
mkdir "$target"

# This is necessary to keep yum happy.  It's not clear why yum can't
# just create this file itself.
mkdir -p "$target"/var/cache/yum/febootstrap/packages

yumargs="-y --disablerepo=* --enablerepo=febootstrap --noplugins --nogpgcheck"

# If we are root, then we don't need to run fakeroot and fakechroot.
if [ $(id -u) -eq 0 ]; then
    yum \
        -c "$tmpdir"/febootstrap.repo \
	$yumargs \
	--installroot="$target" \
	install "${packages[@]}"
else
    fakeroot -s "$target"/fakeroot.log \
    fakechroot -s \
    yum \
	-c "$tmpdir"/febootstrap.repo \
	$yumargs \
	--installroot="$target" \
	install "${packages[@]}"
fi
