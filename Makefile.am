# supermin Makefile.am
# (C) Copyright 2009-2013 Red Hat Inc.
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

ACLOCAL_AMFLAGS = -I m4

SUBDIRS = lib src helper examples tests

EXTRA_DIST = \
	.gitignore \
	.gitmodules \
	autogen.sh \
	html/pod.css \
	m4/gnulib-cache.m4 \
	$(SOURCES)

# Maintainer website update.
HTMLFILES = \
	html/supermin.1.html \
	html/supermin-helper.1.html

WEBSITEDIR = $(HOME)/d/redhat/websites/libguestfs

website: $(HTMLFILES)
	cp $(HTMLFILES) $(WEBSITEDIR)

CLEANFILES = $(HTMLFILES) pod2*.tmp
