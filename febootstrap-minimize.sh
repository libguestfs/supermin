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

unset CDPATH

TEMP=`getopt \
        -o '' \
        --long help,all,none,keep-locales,drop-locales,keep-docs,drop-docs,keep-cracklib,drop-cracklib,keep-i18n,drop-i18n,keep-zoneinfo,drop-zoneinfo,keep-rpmdb,drop-rpmdb,keep-yum-cache,drop-yum-cache,keep-services,drop-services,keep-sln,drop-sln,keep-ldconfig,drop-ldconfig,no-pack-executables,pack-executables \
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
 keep_cracklib=no
     keep_i18n=no
 keep_zoneinfo=no
    keep_rpmdb=no
keep_yum_cache=no
 keep_services=no
      keep_sln=no
 keep_ldconfig=no
}

set_none ()
{
  keep_locales=yes
     keep_docs=yes
 keep_cracklib=yes
     keep_i18n=yes
 keep_zoneinfo=yes
    keep_rpmdb=yes
keep_yum_cache=yes
 keep_services=yes
      keep_sln=yes
 keep_ldconfig=yes
}

set_all
pack_executables=no

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
	--keep-rpmdb)
	    keep_rpmdb=yes
	    shift;;
	--drop-rpmdb)
	    keep_rpmdb=no
	    shift;;
	--keep-yum-cache)
	    keep_yum_cache=yes
	    shift;;
	--drop-yum-cache)
	    keep_yum_cache=no
	    shift;;
	--keep-services)
	    keep_services=yes
	    shift;;
	--drop-services)
	    keep_services=no
	    shift;;
	--keep-sln)
	    keep_sln=yes
	    shift;;
	--drop-sln)
	    keep_sln=no
	    shift;;
	--keep-ldconfig)
	    keep_ldconfig=yes
	    shift;;
	--drop-ldconfig)
	    keep_ldconfig=no
	    shift;;
	--no-pack-executables)
	    pack_executables=no
	    shift;;
	--pack-executables)
	    pack_executables=yes
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

if [ ! -d "$target" ]; then
    echo "febootstrap-minimize: $target: target directory not found"
    exit 1
fi

# Create a temporary directory, make sure it gets cleaned up at the end.
tmpdir=$(mktemp -d)
remove_tmpdir ()
{
  status=$?
  rm -rf "$tmpdir" && exit $status
}
trap remove_tmpdir EXIT

#----------------------------------------------------------------------

if [ "$keep_locales" != "yes" ]; then
    rm -f "$target"/usr/lib/locale/*
    rm -rf "$target"/usr/share/locale
    rm -rf "$target"/usr/lib*/gconv
    rm -f "$target"/usr/bin/localedef
    rm -f "$target"/usr/sbin/build-locale-archive
fi

if [ "$keep_docs" != "yes" ]; then
    rm -rf "$target"/usr/share/man
    rm -rf "$target"/usr/share/doc
    rm -rf "$target"/usr/share/info
    rm -rf "$target"/usr/share/gnome/help
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

if [ "$keep_rpmdb" != "yes" ]; then
    rm -rf "$target"/var/lib/rpm/*
fi

if [ "$keep_yum_cache" != "yes" ]; then
    rm -rf "$target"/var/cache/yum/*
fi

if [ "$keep_services" != "yes" ]; then
    # NB: Overwrite the same file so that we have the same inode,
    # since fakeroot tracks files by inode number.
    cat > "$target"/etc/services <<'__EOF__'
tcpmux 1/tcp
tcpmux 1/udp
echo 7/tcp
echo 7/udp
discard 9/tcp sink null
discard 9/udp sink null
ftp 21/tcp
ftp 21/udp fsp fspd
ssh 22/tcp
ssh 22/udp
telnet 23/tcp
telnet 23/udp
smtp 25/tcp mail
smtp 25/udp mail
time 37/tcp timserver
time 37/udp timserver
nameserver 42/tcp name
nameserver 42/udp name
domain 53/tcp
domain 53/udp
bootps 67/tcp
bootps 67/udp
bootpc 68/tcp dhcpc
bootpc 68/udp dhcpc
tftp 69/tcp
tftp 69/udp
finger 79/tcp
finger 79/udp
http 80/tcp www www-http
http 80/udp www www-http
http 80/sctp
kerberos 88/tcp kerberos5 krb5
kerberos 88/udp kerberos5 krb5
pop3 110/tcp pop-3
pop3 110/udp pop-3
sunrpc 111/tcp portmapper rpcbind
sunrpc 111/udp portmapper rpcbind
auth 113/tcp authentication tap ident
auth 113/udp authentication tap ident
ntp 123/tcp
ntp 123/udp
imap 143/tcp imap2
imap 143/udp imap2
snmp 161/tcp
snmp 161/udp
snmptrap 162/tcp
snmptrap 162/udp snmp-trap
__EOF__
fi

if [ "$keep_sln" != "yes" ]; then
    rm -f "$target"/sbin/sln
fi

if [ "$keep_ldconfig" != "yes" ]; then
    rm -f "$target"/sbin/ldconfig
    rm -f "$target"/etc/ld.so.cache
    rm -rf "$target"/var/cache/ldconfig/*
fi

if [ "$pack_executables" = "yes" ]; then
    # NB. Be careful to keep the same inode number, since fakeroot
    # tracks files by inode number.
    for path in $(find "$target" -type f -perm /111 |
	          xargs file |
		  grep executable |
		  awk -F: '{print $1}'); do
	base=$(basename "$path")
	cp "$path" "$tmpdir"
	(cd "$tmpdir" && upx -q -q --best "$base")
	cat "$tmpdir"/"$base" > "$path"
	rm "$tmpdir"/"$base"
    done
fi
