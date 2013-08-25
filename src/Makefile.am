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

EXTRA_DIST = \
	config.ml \
	supermin.8 \
	supermin.pod \
	supermin.ml \
	supermin_cmdline.mli \
	supermin_cmdline.ml \
	supermin_debian.ml \
	supermin_package_handlers.mli \
	supermin_package_handlers.ml \
	supermin_pacman.ml \
	supermin_urpmi_rpm.ml \
	supermin_poldek_rpm.ml \
	supermin_utils.mli \
	supermin_utils.ml \
	supermin_yum_rpm.ml \
	supermin_zypp_rpm.ml

# Note these must be in build dependency order.
SOURCES = \
	config.ml \
	supermin_cmdline.mli \
	supermin_cmdline.ml \
	supermin_utils.mli \
	supermin_utils.ml \
	supermin_package_handlers.mli \
	supermin_package_handlers.ml

if HAVE_OCAML_INIFILES
SOURCES += \
	supermin_zypp_rpm.ml
endif

SOURCES += \
	supermin_yum_rpm.ml \
	supermin_urpmi_rpm.ml \
	supermin_poldek_rpm.ml \
	supermin_debian.ml \
	supermin_pacman.ml \
	supermin.ml

CLEANFILES = *~ *.cmi *.cmo *.cmx *.o supermin

man_MANS = \
	supermin.8

bin_SCRIPTS = supermin

SOURCES_ML = $(filter %.ml,$(SOURCES))
BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(SOURCES_ML:.ml=.cmx)

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
BEST    = c
else
OBJECTS = $(XOBJECTS)
BEST    = opt
endif

OCAMLPACKAGES = -package unix,str
if HAVE_OCAML_INIFILES
OCAMLPACKAGES += -package inifiles
endif
OCAMLFLAGS = -warn-error CDEFLMPSUVXYZ

supermin: $(OBJECTS)
	$(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) -linkpkg \
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
	$(OCAMLFIND) ocamldep $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) 's/ :/:/' | \
	  sort > $@-t
	mv $@-t $@

include .depend

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly

if HAVE_PERLDOC

supermin.8: supermin.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

noinst_DATA = \
	../html/supermin.8.html

../html/supermin.8.html: supermin.pod
	mkdir -p ../html
	pod2html \
	  --css 'pod.css' \
	  --htmldir ../html \
	  --outfile ../html/supermin.8.html \
	  supermin.pod

endif
