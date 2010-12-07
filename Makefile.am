# febootstrap Makefile.am
# (C) Copyright 2009-2010 Red Hat Inc.
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

SUBDIRS = lib helper

# Note these must be in build dependency order.
SOURCES = \
	config.ml \
	febootstrap_utils.mli \
	febootstrap_utils.ml \
	febootstrap_cmdline.mli \
	febootstrap_cmdline.ml \
	febootstrap_package_handlers.mli \
	febootstrap_package_handlers.ml \
	febootstrap_yum_rpm.ml \
	febootstrap_debian.ml \
	febootstrap_pacman.ml \
	febootstrap.ml

CLEANFILES = *~ *.cmi *.cmo *.cmx *.o febootstrap

EXTRA_DIST = \
	.gitignore \
	.gitmodules \
	autogen.sh \
	febootstrap.8 \
	febootstrap.pod \
	m4/gnulib-cache.m4 \
	$(SOURCES)

man_MANS = \
	febootstrap.8

bin_SCRIPTS = febootstrap

SOURCES_ML = $(filter %.ml,$(SOURCES))
BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(SOURCES_ML:.ml=.cmx)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

OCAMLPACKAGES = -package unix,str
OCAMLFLAGS = -warn-error CDEFLMPSUVXYZ

febootstrap: $(OBJECTS)
	$(OCAMLFIND) $(OCAMLBEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) -linkpkg \
	  $^ -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@

depend: .depend

.depend: $(SOURCES)
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep $^ > $@-t
	mv $@-t $@

include .depend

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly

if HAVE_PERLDOC

febootstrap.8: febootstrap.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

noinst_DATA = \
	html/febootstrap.8.html

html/febootstrap.8.html: febootstrap.pod
	mkdir -p html
	pod2html \
	  --css 'pod.css' \
	  --htmldir html \
	  --outfile html/febootstrap.8.html \
	  febootstrap.pod

endif

# Maintainer website update.
HTMLFILES = \
	html/febootstrap.8.html \
	html/febootstrap-supermin-helper.8.html

WEBSITEDIR = $(HOME)/d/redhat/websites/libguestfs

website: $(HTMLFILES)
	cp $(HTMLFILES) $(WEBSITEDIR)

CLEANFILES += $(HTMLFILES) pod2*.tmp
