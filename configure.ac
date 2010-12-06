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

AC_INIT(febootstrap,3.0)
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

dnl Optional programs.
AC_CHECK_PROG(PERLDOC,[perldoc],[perldoc],[no])
if test "x$PERLDOC" = "xno" ; then
  AC_MSG_WARN([perldoc not found - install perl to make man pages])
fi
AM_CONDITIONAL(HAVE_PERLDOC,[test "$perldoc" != "no"])

dnl For yum-rpm handler.
AC_CHECK_PROG(YUM,[yum],[yum],[no])
AC_CHECK_PROG(RPM,[rpm],[rpm],[no])
AC_CHECK_PROG(YUMDOWNLOADER,[yumdownloader],[yumdownloader],[no])

dnl For Debian handler.
AC_CHECK_PROG(APTITUDE,[aptitude],[aptitude],[no])
AC_CHECK_PROG(DPKG,[dpkg],[dpkg],[no])

dnl Required programs, libraries.
AC_PATH_PROG([INSMODSTATIC],[insmod.static],[no])
if test "x$INSMODSTATIC" = "xno" ; then
  AC_MSG_FAILURE([insmod.static program not found

Is /sbin in your current path?

Note that Debian/Ubuntu do not package this file from module-init-tools.
Sorry, please fix your distribution.  In the meantime you can copy
/sbin/insmod.static from a Fedora machine.
])
fi
AC_DEFINE_UNQUOTED([INSMODSTATIC],["$INSMODSTATIC"],
  [Full path to the insmod.static program.])

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
AC_CONFIG_FILES([config.ml Makefile lib/Makefile helper/Makefile])
AC_OUTPUT
