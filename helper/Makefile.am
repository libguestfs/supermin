# febootstrap Makefile.am
# (C) Copyright 2010 Red Hat Inc.
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

bin_PROGRAMS = \
	febootstrap-supermin-helper

febootstrap_supermin_helper_SOURCES = \
	helper.h \
	appliance.c \
	checksum.c \
	cpio.c \
	ext2.c \
	ext2cpio.c \
	ext2initrd.c \
	ext2internal.h \
	kernel.c \
	main.c \
	utils.c
febootstrap_supermin_helper_CFLAGS = -Wall -I../lib
febootstrap_supermin_helper_LDADD = \
	ext2init.o -lext2fs -lcom_err $(LTLIBINTL) -L../lib -lgnu

# init "script" used by ext2 initrd.
noinst_PROGRAMS = init
init_SOURCES = init.c
init_CFLAGS = -static
init_LDFLAGS = -static

CLEANFILES = ext2init.S

ext2init.o: ext2init.S
	$(CC) -o $@ -c $<

ext2init.S: init
	strip --strip-all $<
	@file $< | grep -isq static || \
	  (echo "*** error: init is not staticly linked"; exit 1)
	./bin2s.pl $< $@

man_MANS = \
	febootstrap-supermin-helper.8

if HAVE_PERLDOC

febootstrap-supermin-helper.8: febootstrap-supermin-helper.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

noinst_DATA = \
	$(top_builddir)/html/febootstrap-supermin-helper.8.html

$(top_builddir)/html/febootstrap-supermin-helper.8.html: febootstrap-supermin-helper.pod
	mkdir -p $(top_builddir)/html
	cd $(top_builddir) && pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/febootstrap-supermin-helper.8.html \
	  helper/febootstrap-supermin-helper.pod

endif

EXTRA_DIST = \
	febootstrap-supermin-helper.8 \
	febootstrap-supermin-helper.pod \
	bin2s.pl
