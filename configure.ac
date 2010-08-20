dnl febootstrap configure.ac
dnl (C) Copyright 2009-2010 Red Hat Inc.
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

AC_INIT(febootstrap,2.7)
AM_INIT_AUTOMAKE

dnl Check for basic C environment.
AC_PROG_CC_STDC
gl_EARLY

AC_PROG_INSTALL
AC_PROG_CPP

AC_C_PROTOTYPES
test "x$U" != "x" && AC_MSG_ERROR([Compiler not ANSI compliant])

AM_PROG_CC_C_O

dnl Check support for 64 bit file offsets.
AC_SYS_LARGEFILE

gl_INIT

AC_CHECK_PROG(PERLDOC,[perldoc],[perldoc],[no])
if test "x$PERLDOC" = "xno" ; then
  AC_MSG_WARN([perldoc not found - install perl to make man pages])
fi
AM_CONDITIONAL(HAVE_PERLDOC,[test "$perldoc" != "no"])

AC_CHECK_PROG(FAKEROOT,[fakeroot],[fakeroot],[no])
if test "x$FAKEROOT" = "xno" ; then
  AC_MSG_FAILURE([fakeroot program not found])
fi

AC_CHECK_PROG(FAKECHROOT,[fakechroot],[fakechroot],[no])
if test "x$FAKECHROOT" = "xno" ; then
  AC_MSG_FAILURE([fakechroot program not found])
fi

AC_CHECK_PROG(YUM,[yum],[yum],[no])
if test "x$YUM" = "xno" ; then
  AC_MSG_FAILURE([yum program not found])
fi

AC_PATH_PROG([MKE2FS],[mke2fs],[no])
if test "x$MKE2FS" = "xno" ; then
  AC_MSG_FAILURE([mke2fs program not found (is /sbin in your current path?)])
fi
AC_DEFINE_UNQUOTED([MKE2FS],["$MKE2FS"],
  [Full path to the mke2fs program.])

old_LIBS="$LIBS"
AC_CHECK_LIB([com_err],[error_message],[],[
  AC_MSG_FAILURE([com_err library not found (part of e2fsprogs)])
])
LIBS="$old_LIBS"

old_LIBS="$LIBS"
AC_CHECK_LIB([ext2fs],[ext2fs_file_open2],[],[
  AC_MSG_FAILURE([libext2fs library not found (part of e2fsprogs)])
])
LIBS="$old_LIBS"

AC_CHECK_HEADER([ext2fs/ext2fs.h],[],[
  AC_MSG_FAILURE([Header <ext2fs/ext2fs.h> not found (part of e2fsprogs)])
])

AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile lib/Makefile helper/Makefile examples/Makefile])
AC_OUTPUT
