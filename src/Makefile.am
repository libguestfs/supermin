# supermin Makefile.am
# (C) Copyright 2009-2014 Red Hat Inc.
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
	.depend \
	bin2s.pl \
	config.ml.in \
	supermin.1 \
	supermin.pod \
	$(SOURCES)

# Note these must be in build dependency order.
SOURCES = \
	ext2fs-c.c \
	ext2fs.ml \
	ext2fs.mli \
	ext2init-c.c \
	ext2init.ml \
	ext2init.mli \
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
	package_handler.ml \
	package_handler.mli \
	rpm.ml \
	dpkg.ml \
	pacman.ml \
	prepare.ml \
	chroot.ml \
	kernel.ml \
	ext2_initrd.ml \
	ext2.ml \
	build.ml \
	supermin.ml

# Can't use filter for this because of automake brokenness.
SOURCES_ML = \
	ext2fs.ml \
	ext2init.ml \
	fnmatch.ml \
	glob.ml \
	realpath.ml \
	librpm.ml \
	config.ml \
	utils.ml \
	types.ml \
	package_handler.ml \
	rpm.ml \
	dpkg.ml \
	pacman.ml \
	prepare.ml \
	chroot.ml \
	kernel.ml \
	ext2_initrd.ml \
	ext2.ml \
	build.ml \
	supermin.ml

SOURCES_C = \
	ext2fs-c.c \
	ext2init-c.c \
	fnmatch-c.c \
	glob-c.c \
	librpm-c.c \
	realpath-c.c

CLEANFILES = *~ *.cmi *.cmo *.cmx *.o supermin

man_MANS = \
	supermin.1

bin_PROGRAMS = supermin

supermin_SOURCES = $(SOURCES_C)
supermin_CFLAGS = \
	-I$(shell $(OCAMLC) -where) \
	$(EXT2FS_CFLAGS) $(COM_ERR_CFLAGS) $(LIBRPM_CFLAGS) \
	-Wall $(WERROR_CFLAGS) \
	-I$(top_srcdir)/lib -I../lib

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

supermin_DEPENDENCIES = $(OBJECTS) ext2init-bin.o

supermin_LDADD = ext2init-bin.o ../lib/libgnu.a

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

# init "script" used by ext2 initrd.
noinst_PROGRAMS = init
init_SOURCES = init.c
init_CFLAGS = -static
init_LDFLAGS = -static
init_LDADD = $(ZLIB_STATIC_LIBS) $(LZMA_STATIC_LIBS)

CLEANFILES += ext2init-bin.S

ext2init-bin.o: ext2init-bin.S
	$(CC) -o $@ -c $<

ext2init-bin.S: init $(srcdir)/bin2s.pl
	strip --strip-all $<
	@file $< | grep -isq static || \
	  (echo "*** error: init is not statically linked"; exit 1)
	$(srcdir)/bin2s.pl $< $@

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
