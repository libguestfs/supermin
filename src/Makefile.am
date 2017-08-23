# supermin Makefile.am
# (C) Copyright 2009-2016 Red Hat Inc.
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

EXTRA_DIST = \
	.depend \
	bin2c.pl \
	config.ml.in \
	supermin.1 \
	supermin.pod \
	$(SOURCES)

# Note these must be in build dependency order.
SOURCES = \
	ext2fs-c.c \
	ext2fs.ml \
	ext2fs.mli \
	fnmatch-c.c \
	fnmatch.ml \
	fnmatch.mli \
	glob-c.c \
	glob.ml \
	glob.mli \
	realpath-c.c \
	realpath.ml \
	realpath.mli \
	librpm-c.c \
	librpm.ml \
	librpm.mli \
	config.ml \
	utils.ml \
	utils.mli \
	types.ml \
	os_release.ml \
	os_release.mli \
	package_handler.ml \
	package_handler.mli \
	ph_rpm.ml \
	ph_rpm.mli \
	ph_dpkg.ml \
	ph_dpkg.mli \
	ph_pacman.ml \
	ph_pacman.mli \
	mode_prepare.ml \
	mode_prepare.mli \
	format_chroot.ml \
	format_chroot.mli \
	format-ext2-init-c.c \
	format_ext2_init.ml \
	format_ext2_init.mli \
	format_ext2_initrd.ml \
	format_ext2_initrd.mli \
	format_ext2_kernel.ml \
	format_ext2_kernel.mli \
	format_ext2.ml \
	format_ext2.mli \
	mode_build.ml \
	mode_build.mli \
	supermin.ml

# Can't use filter for this because of automake brokenness.
SOURCES_ML = \
	ext2fs.ml \
	fnmatch.ml \
	glob.ml \
	realpath.ml \
	librpm.ml \
	config.ml \
	utils.ml \
	types.ml \
	os_release.ml \
	package_handler.ml \
	ph_rpm.ml \
	ph_dpkg.ml \
	ph_pacman.ml \
	mode_prepare.ml \
	format_chroot.ml \
	format_ext2_init.ml \
	format_ext2_initrd.ml \
	format_ext2_kernel.ml \
	format_ext2.ml \
	mode_build.ml \
	supermin.ml

SOURCES_C = \
	ext2fs-c.c \
	format-ext2-init-c.c \
	fnmatch-c.c \
	glob-c.c \
	librpm-c.c \
	realpath-c.c

CLEANFILES = *~ *.cmi *.cmo *.cmx *.o supermin

man_MANS = \
	supermin.1

bin_PROGRAMS = supermin

supermin_SOURCES = $(SOURCES_C)
nodist_supermin_SOURCES = format-ext2-init-bin.h
supermin_CFLAGS = \
	-I$(shell $(OCAMLC) -where) \
	$(EXT2FS_CFLAGS) $(COM_ERR_CFLAGS) $(LIBRPM_CFLAGS) \
	-Wall $(WERROR_CFLAGS) \
	-I$(top_srcdir)/lib -I../lib
format-ext2-init-c.$(OBJEXT): format-ext2-init-bin.h

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(SOURCES_ML:.ml=.cmx)

OCAMLPACKAGES = -package unix,str
OCAMLFLAGS = -warn-error CDEFLMPSUVXYZ-3

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
BEST    = c
OCAMLFLAGS += -custom
else
OBJECTS = $(XOBJECTS)
BEST    = opt
endif

supermin_DEPENDENCIES = $(OBJECTS)

supermin_LDADD = ../lib/libgnu.a

supermin_LINK = \
	./supermin-link.sh \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) \
	  $(OBJECTS) -o $@

.mli.cmi:
	$(OCAMLFIND) ocamlc $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
.ml.cmo:
	$(OCAMLFIND) ocamlc $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@
.ml.cmx:
	$(OCAMLFIND) ocamlopt $(OCAMLFLAGS) $(OCAMLPACKAGES) -c $< -o $@

CLEANFILES += format-ext2-init-bin.h
BUILT_SOURCES = format-ext2-init-bin.h

format-ext2-init-bin.h: ../init/init $(srcdir)/bin2c.pl
	strip --strip-all $<
	ls -l $<
	@file $< | grep -isq static || \
	  (echo "*** error: init is not statically linked"; exit 1)
	$(srcdir)/bin2c.pl $< $@

depend: .depend

.depend: $(wildcard $(abs_srcdir)/*.mli) $(wildcard $(abs_srcdir)/*.ml) config.ml
	rm -f $@ $@-t
	$(OCAMLFIND) ocamldep -I $(abs_srcdir) -I $(builddir) $^ | \
	  $(SED) 's/ *$$//' | \
	  $(SED) -e :a -e '/ *\\$$/N; s/ *\\\n */ /; ta' | \
	  $(SED) -e 's,$(abs_srcdir)/,$(builddir)/,g' | \
	  sort > $@-t
	mv $@-t $@

-include .depend

SUFFIXES = .cmo .cmi .cmx .ml .mli .mll .mly

if HAVE_PERLDOC

supermin.1: $(srcdir)/supermin.pod
	pod2man \
	  -u \
	  --section 1 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

noinst_DATA = \
	../html/supermin.1.html

../html/supermin.1.html: $(srcdir)/supermin.pod
	mkdir -p ../html
	pod2html \
	  --css 'pod.css' \
	  --htmldir ../html \
	  --outfile ../html/supermin.1.html \
	  $<

endif
