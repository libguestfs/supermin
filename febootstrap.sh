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
        --long groupinstall:,group-install:,help,install:,noclean,no-clean \
        -n febootstrap -- "$@"`
if [ $? != 0 ]; then
    echo "febootstrap: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

declare -a packages
packages[0]="@Core"
i=0

clean=yes

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
	--noclean|--no-clean)
	    clean=no
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
case $arch in
    i?86) arch=i386 ;;
esac

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

# Target must be an absolute path.
target=$(cd "$target"; pwd)

# This is necessary to keep yum happy.  It's not clear why yum can't
# just create this file itself.
mkdir -p "$target"/var/cache/yum/febootstrap/packages

# NB: REQUIRED for useradd/groupadd to run properly.
#
# However this causes 'filesystem' RPM install to give the
# following error.  Not sure how serious the error is:
# error: unpacking of archive failed on file /proc: cpio: utime
export FAKECHROOT_EXCLUDE_PATH=/proc

# Substitute some statically-linked commands.  This is only supported
# in fakechroot > 2.9.  For previous versions of fakechroot it is
# ignored.
export FAKECHROOT_CMD_SUBST=/sbin/ldconfig=/bin/true:/usr/sbin/glibc_post_upgrade.i686=/bin/true:/usr/sbin/glibc_post_upgrade.x86_64=/bin/true

# Make the device nodes inside the fake chroot.
# (Copied from mock/backend.py)  Why isn't there a base package which
# creates these?
make_device_nodes ()
{
    mkdir "$target"/proc
    mkdir "$target"/sys
    mkdir "$target"/dev
    (
	cd "$target"/dev
	mkdir pts
	mkdir shm
	mkdir mapper
	mknod null c 1 3;    chmod 0666 null
	mknod full c 1 7;    chmod 0666 full
	mknod zero c 1 5;    chmod 0666 zero
	mknod random c 1 8;  chmod 0666 random
	mknod urandom c 1 9; chmod 0444 urandom
	mknod tty c 5 0;     chmod 0666 tty
	mknod console c 5 1; chmod 0600 console
	mknod ptmx c 5 2;    chmod 0666 ptmx
	ln -sf /proc/self/fd/0 stdin
	ln -sf /proc/self/fd/1 stdout
	ln -sf /proc/self/fd/2 stderr
    )
}
export -f make_device_nodes
export target

if [ $(id -u) -ne 0 ]; then
    fakeroot -s "$target"/fakeroot.log \
    make_device_nodes
else
    make_device_nodes
fi

# Run yum.
run_yum ()
{
    yum \
	-y -c "$tmpdir"/febootstrap.repo \
	--disablerepo=* --enablerepo=febootstrap \
	--noplugins --nogpgcheck \
	--installroot="$target" \
	install "$@"
}
export -f run_yum
export tmpdir

if [ $(id -u) -ne 0 ]; then
    # Bash doesn't support exporting array variables, hence this
    # tortuous workaround.
    fakeroot -i "$target"/fakeroot.log -s "$target"/fakeroot.log \
    fakechroot -s \
    bash -c 'run_yum "$@"' run_yum "${packages[@]}"
else
    run_yum "${packages[@]}"
fi

# Clean up the yum repository.
if [ "$clean" = "yes" ]; then
    rm -rf "$target"/var/cache/yum/febootstrap
fi
