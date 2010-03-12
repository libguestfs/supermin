#!/bin/bash -
# febootstrap-to-supermin
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
        --long help \
        -n febootstrap-to-supermin -- "$@"`
if [ $? != 0 ]; then
    echo "febootstrap-to-supermin: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

usage ()
{
    echo "Usage: febootstrap-to-supermin DIR supermin.img hostfiles.txt"
    echo "Please read febootstrap-to-supermin(8) man page for more information."
}

while true; do
    case "$1" in
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

if [ $# -ne 3 ]; then
    usage
    exit 1
fi

set -e

# Create a temporary directory, make sure it gets cleaned up at the end.
tmpdir=$(mktemp -d)
remove_tmpdir ()
{
  status=$?
  rm -rf "$tmpdir" && exit $status
}
trap remove_tmpdir EXIT

# Get the complete list of files and directories in the appliance.
(cd "$1" > /dev/null && find) > "$tmpdir/files"

exec 5>"$tmpdir/keep"		# Files/dirs we will keep in supermin.img
exec 6>$3			# hostfiles.txt (output)
exec 7<"$tmpdir/files"

while read path <&7; do
    dir=$(dirname "$path")
    file=$(basename "$path")

    # For quoting problems with the bash =~ operator, see bash FAQ
    # question E14 here http://tiswww.case.edu/php/chet/bash/FAQ and
    # http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=487387#25
    # (RHBZ#566511).
    p_etc='^\./etc'
    p_dev='^\./dev'
    p_var='^\./var'
    p_lib_modules='^\./lib/modules/'
    p_builddir='^\./builddir'
    p_ld_so='^ld-[.0-9]+\.so$'
    p_libbfd='^libbfd-.*\.so$'
    p_libgcc='^libgcc_s-.*\.so\.([0-9]+)$'
    p_libntfs3g='^libntfs-3g\.so\..*$'
    p_lib123so='^lib(.*)-[-.0-9]+\.so$'
    p_lib123so123='^lib(.*)-[-.0-9]+\.so\.([0-9]+)\.'
    p_libso123='^lib(.*)\.so\.([0-9]+)\.'

    # Ignore fakeroot.log.
    if [ "$path" = "./fakeroot.log" ]; then
	:

    # All we're going to keep are the special files /init, the daemon,
    # configuration files (/etc), devices and modifiable stuff (/var).
    elif [ "$path" = "./init" ]; then
        echo "$path" >&5

    elif [[ "$path" =~ $p_etc || "$path" =~ $p_dev || "$path" =~ $p_var ]]
    then
        echo "$path" >&5

    # Kernel modules are always copied in from the host, including all
    # the dependency information files.
    elif [[ "$path" =~ $p_lib_modules ]]; then
	:

    # On mock/Koji, exclude bogus /builddir directory which for some
    # reason contains some yum temporary files (RHBZ#566512).
    elif [[ "$path" =~ $p_builddir ]]; then
        :

    # Always write directory names to both output files.
    elif [ -d "$path" ]; then
        echo "$path" >&5
        echo "$path" >&6

    # Some libraries need fixed version numbers replaced by wildcards.

    elif [[ "$file" =~ $p_ld_so ]]; then
        echo "$dir/ld-*.so" >&6

    # Special case for libbfd
    elif [[ "$file" =~ $p_libbfd ]]; then
        echo "$dir/libbfd-*.so" >&6

    # Special case for libgcc_s-<gccversion>-<date>.so.N
    elif [[ "$file" =~ $p_libgcc ]]; then
        echo "$dir/libgcc_s-*.so.${BASH_REMATCH[1]}" >&6

    # Special case for libntfs-3g.so.*
    elif [[ "$file" =~ $p_libntfs3g ]]; then
       [ -n "$libntfs3g_once" ] || echo "$dir/libntfs-3g.so.*" >&6
       libntfs3g_once=1

    # libfoo-1.2.3.so
    elif [[ "$file" =~ $p_lib123so ]]; then
        echo "$dir/lib${BASH_REMATCH[1]}-*.so" >&6

    # libfoo-1.2.3.so.1.2.3 (but NOT '*.so.N')
    elif [[ "$file" =~ $p_lib123so123 ]]; then
        echo "$dir/lib${BASH_REMATCH[1]}-*.so.${BASH_REMATCH[2]}.*" >&6

    # libfoo.so.1.2.3 (but NOT '*.so.N')
    elif [[ "$file" =~ $p_libso123 ]]; then
        echo "$dir/lib${BASH_REMATCH[1]}.so.${BASH_REMATCH[2]}.*" >&6

    else
        # Anything else comes from the host directly.
        echo "$path" >&6
    fi
done

# Close output files.
exec 5>&-
exec 6>&-

# Now run febootstrap-to-initramfs to construct the supermin
# appliance.
if ! febootstrap-to-initramfs --nocompress --files="$tmpdir/keep" "$1" > "$2"
then
    rm -f "$2"
fi
