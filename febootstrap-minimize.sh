#!/bin/bash -
# febootstrap minimize
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
        -o '' \
        --long help,all,none,keep-locales,drop-locales,keep-docs,drop-docs,keep-yum-cache,drop-yum-cache,keep-cracklib,drop-cracklib,keep-i18n,drop-i18n,keep-zoneinfo,drop-zoneinfo \
        -n febootstrap-minimize -- "$@"`
if [ $? != 0 ]; then
    echo "febootstrap-minimize: problem parsing the command line arguments"
    exit 1
fi
eval set -- "$TEMP"

set_all ()
{
  keep_locales=no
     keep_docs=no
keep_yum_cache=no
 keep_cracklib=no
     keep_i18n=no
 keep_zoneinfo=no
}

set_none ()
{
  keep_locales=yes
     keep_docs=yes
keep_yum_cache=yes
 keep_cracklib=yes
     keep_i18n=yes
 keep_zoneinfo=yes
}

set_all

usage ()
{
    echo "Usage: febootstrap-minimize [--options] DIR"
    echo "Please read febootstrap-minimize(8) man page for more information."
}

while true; do
    case "$1" in
	--all)
	    set_all
	    shift;;
	--none)
	    set_none
	    shift;;
	--keep-locales)
	    keep_locales=yes
	    shift;;
	--drop-locales)
	    keep_locales=no
	    shift;;
	--keep-docs)
	    keep_docs=yes
	    shift;;
	--drop-docs)
	    keep_docs=no
	    shift;;
	--keep-yum-cache)
	    keep_yum_cache=yes
	    shift;;
	--drop-yum-cache)
	    keep_yum_cache=no
	    shift;;
	--keep-cracklib)
	    keep_cracklib=yes
	    shift;;
	--drop-cracklib)
	    keep_cracklib=no
	    shift;;
	--keep-i18n)
	    keep_i18n=yes
	    shift;;
	--drop-i18n)
	    keep_i18n=no
	    shift;;
	--keep-zoneinfo)
	    keep_zoneinfo=yes
	    shift;;
	--drop-zoneinfo)
	    keep_zoneinfo=no
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

#----------------------------------------------------------------------

if [ ! -d "$target" ]; then
    echo "febootstrap-minimize: $target: target directory not found"
    exit 1
fi

#du -sh "$target"

if [ "$keep_locales" != "yes" ]; then
    rm -f "$target"/usr/lib/locale/*
    rm -rf "$target"/usr/share/locale
fi

if [ "$keep_docs" != "yes" ]; then
    rm -rf "$target"/usr/share/man
    rm -rf "$target"/usr/share/doc
fi

if [ "$keep_yum_cache" != "yes" ]; then
    rm -rf "$target"/var/cache/yum/*
fi

if [ "$keep_cracklib" != "yes" ]; then
    rm -rf "$target"/usr/share/cracklib
fi

if [ "$keep_i18n" != "yes" ]; then
    rm -rf "$target"/usr/share/i18n
fi

if [ "$keep_zoneinfo" != "yes" ]; then
    mv "$target"/usr/share/zoneinfo/{UCT,UTC,Universal,Zulu,GMT*,*.tab} \
      "$target"
    rm -rf "$target"/usr/share/zoneinfo/*
    mv "$target"/{UCT,UTC,Universal,Zulu,GMT*,*.tab} \
      "$target"/usr/share/zoneinfo/
fi
