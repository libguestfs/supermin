dnl supermin configure.ac
dnl (C) Copyright 2009-2014 Red Hat Inc.
dnl
dnl This program is free software; you can redistribute it and/or modify
dnl it under the terms of the GNU General Public License as published by
dnl the Free Software Foundation; either version 2 of the License, or
dnl (at your option) any later version.
dnl
dnl This program is distributed in the hope that it will be useful,
dnl but WITHOUT ANY WARRANTY; without even the implied warranty of
dnl MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
dnl GNU General Public License for more details.
dnl
dnl You should have received a copy of the GNU General Public License
dnl along with this program; if not, write to the Free Software
dnl Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
dnl
dnl Written by Richard W.M. Jones <rjones@redhat.com>

AC_INIT([supermin],[5.1.8])
AM_INIT_AUTOMAKE(foreign)

dnl Check for basic C environment.
AC_PROG_CC_STDC
gl_EARLY

AC_PROG_INSTALL
AC_PROG_CPP

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AM_PROG_CC_C_O

dnl Gnulib
gl_INIT

dnl Check support for 64 bit file offsets.
AC_SYS_LARGEFILE

dnl Enable GNU stuff.
AC_USE_SYSTEM_EXTENSIONS

dnl Define the host CPU architecture (defines host_cpu).
AC_CANONICAL_HOST

# Define $(SED).
m4_ifdef([AC_PROG_SED],[
    AC_PROG_SED
],[
    dnl ... else hope for the best
    AC_SUBST([SED], "sed")
])

# OCaml and ocamlfind are required to compile.
AC_PROG_OCAML
if test "$OCAMLC" = "no"; then
    AC_MSG_ERROR([You must install the OCaml compiler])
fi
AM_CONDITIONAL([HAVE_OCAMLOPT],[test "$OCAMLBEST" = "opt"])
AC_PROG_FINDLIB
if test "$OCAMLFIND" = "no"; then
    AC_MSG_ERROR([You must install OCaml findlib (the ocamlfind command)])
fi

# NB: AC_CHECK_PROG(S) or AC_PATH_PROG(S)?
# Use AC_CHECK_PROG(S) for programs which are only used during build.
# Use AC_PATH_PROG(S) for program names which are compiled into the
# binary and used at run time.  The reason is so that we know which
# programs the binary actually uses.

dnl Optional programs.
AC_CHECK_PROG(PERLDOC,[perldoc],[perldoc],[no])
if test "x$PERLDOC" = "xno" ; then
  AC_MSG_WARN([perldoc not found - install perl to make man pages])
fi
AM_CONDITIONAL(HAVE_PERLDOC,[test "$perldoc" != "no"])

dnl For yum-rpm handler.
AC_PATH_PROG(RPM,[rpm],[no])
AC_PATH_PROG(RPM2CPIO,[rpm2cpio],[no])
AC_PATH_PROG(YUMDOWNLOADER,[yumdownloader],[no])

dnl For Zypper handler.
AC_PATH_PROG(ZYPPER,[zypper],[no])

dnl For URPMI handler.
AC_PATH_PROG(URPMI,[urpmi],[no], [$PATH$PATH_SEPARATOR/usr/sbin])

dnl For Debian handler.
AC_PATH_PROG(APT_GET,[apt-get],[no])
AC_PATH_PROG(DPKG,[dpkg],[no])
AC_PATH_PROG(DPKG_DEB,[dpkg-deb],[no])
AC_PATH_PROG(DPKG_QUERY,[dpkg-query],[no])
AC_PATH_PROG(DPKG_DIVERT,[[dpkg-divert]],[no])

dnl For FrugalWare handler (currently disabled).
AC_PATH_PROG(PACMAN_G2,[pacman-g2],[no])

dnl For ArchLinux handler.
AC_PATH_PROG(PACMAN,[pacman],[no])
AC_PATH_PROG(PACTREE,[pactree],[no])
AC_PATH_PROG(MAKEPKG,[makepkg],[no])

dnl Check for fakeroot, only used a few drivers where the host package
dnl manager contains broken/unnecessary tests for root privs.
AC_PATH_PROG(FAKEROOT,[fakeroot],[no])

dnl Support for compressed input files, gzipped kernel modules.
AC_CHECK_HEADER([zlib.h],[
    AC_CHECK_LIB([z],[gzopen],[
        zlib=yes
        ZLIB_LIBS=-lz

        AC_MSG_CHECKING([for gzip static library])
        old_CFLAGS="$CFLAGS"
        old_LDFLAGS="$LDFLAGS"
        old_LIBS="$LIBS"
        CFLAGS="$CFLAGS -static"
        LDFLAGS="$LDFLAGS -static"
        LIBS="$LIBS -lz"
        AC_LINK_IFELSE([
            #include <stdio.h>
            #include <stdlib.h>
            #include <zlib.h>
            int main () { gzFile g = gzopen ("test", "rb"); exit (g ? 1 : 0); }
        ],[
            zlib_static=yes
            ZLIB_STATIC_LIBS="$ZLIB_LIBS"
            AC_MSG_RESULT([yes])
        ],[
            AC_MSG_RESULT([no])
        ])
        CFLAGS="$old_CFLAGS"
        LDFLAGS="$old_LDFLAGS"
        LIBS="$old_LIBS"
    ])
])
if test "x$zlib" = "xyes"; then
    AC_DEFINE([HAVE_ZLIB],[1],[Define if you have zlib])
    AC_SUBST([ZLIB_LIBS])
fi
if test "x$zlib_static" = "xyes"; then
    AC_DEFINE([HAVE_ZLIB_STATIC],[1],[Define if you have static zlib])
    AC_SUBST([ZLIB_STATIC_LIBS])
fi

dnl Support for xzed kernel modules.
AC_CHECK_HEADER([lzma.h],[
    AC_CHECK_LIB([lzma],[lzma_code],[
        AC_MSG_CHECKING([for xz static library])
        old_CFLAGS="$CFLAGS"
        old_LDFLAGS="$LDFLAGS"
        old_LIBS="$LIBS"
        CFLAGS="$CFLAGS -static"
        LDFLAGS="$LDFLAGS -static"
        LIBS="$LIBS -llzma"
        AC_LINK_IFELSE([
            #include <stdio.h>
            #include <stdlib.h>
            #include <lzma.h>
            int main () { lzma_stream s = LZMA_STREAM_INIT;
                 exit (s.next_in == NULL ? 1 : 0); }
        ],[
            lzma_static=yes
            LZMA_STATIC_LIBS="-llzma"
            AC_MSG_RESULT([yes])
        ],[
            AC_MSG_RESULT([no])
        ])
        CFLAGS="$old_CFLAGS"
        LDFLAGS="$old_LDFLAGS"
        LIBS="$old_LIBS"
    ])
])
if test "x$lzma_static" = "xyes"; then
    AC_DEFINE([HAVE_LZMA_STATIC],[1],[Define if you have static lzma])
    AC_SUBST([LZMA_STATIC_LIBS])
fi

dnl mke2fs.
AC_PATH_PROG([MKE2FS],[mke2fs],[no],
             [$PATH$PATH_SEPARATOR/sbin$PATH_SEPARATOR])
if test "x$MKE2FS" = "xno" ; then
  AC_MSG_FAILURE([mke2fs program not found])
fi
AC_SUBST([MKE2FS])

dnl RHEL 5 mke2fs needed -T <fs> instead of -t <fs>.  Unhelpfully
dnl the --help output doesn't mention this, so we have to test it.
AC_MSG_CHECKING([$MKE2FS -t or -T])
rm -f conftest.img
dd if=/dev/zero of=conftest.img bs=1024 count=1024 >&AS_MESSAGE_LOG_FD 2>&1
if $MKE2FS -t ext2 -F -q conftest.img >&AS_MESSAGE_LOG_FD 2>&1 ; then
  MKE2FS_T_OPTION=-t
elif $MKE2FS -T ext2 -F -q conftest.img >&AS_MESSAGE_LOG_FD 2>&1 ; then
  MKE2FS_T_OPTION=-T
else
  AC_MSG_ERROR([$MKE2FS cannot create filesystems])
fi
rm conftest.img
AC_MSG_RESULT([$MKE2FS_T_OPTION])
AC_SUBST([MKE2FS_T_OPTION])

dnl ext2fs, com_err.
PKG_CHECK_MODULES([EXT2FS], [ext2fs])
PKG_CHECK_MODULES([COM_ERR], [com_err])

dnl Requires ext2fs_close2 function, added in 2011.
old_LIBS="$LIBS"
LIBS="$EXT2FS_LIBS $COM_ERR_LIBS"
AC_CHECK_FUNCS([ext2fs_close2])
LIBS="$old_LIBS"

dnl GNU awk.
AC_CHECK_PROG(GAWK,[gawk],[gawk],[no])
if test "x$GAWK" = "xno" ; then
  AC_MSG_FAILURE([gawk (GNU awk) not found])
fi

dnl cpio
AC_PATH_PROG([CPIO],[cpio],[no])
test "x$CPIO" = "xno" &&
    AC_MSG_ERROR([cpio must be installed])

dnl Disable network tests.
AC_ARG_ENABLE([network-tests],
    [AS_HELP_STRING([--disable-network-tests],
                    [Disable tests that need a network connection.])],
    [],
    [enable_network_tests=yes])
AM_CONDITIONAL([NETWORK_TESTS],
               [test "x$enable_network_tests" = "xyes"])

AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([src/supermin-link.sh],
		[chmod +x,-w src/supermin-link.sh])
AC_CONFIG_FILES([Makefile
        examples/Makefile
        lib/Makefile
        src/config.ml
        src/Makefile
        tests/Makefile])
AC_OUTPUT
