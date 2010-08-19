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

SUBDIRS = lib helper examples

bin_SCRIPTS = \
	febootstrap \
	febootstrap-run \
	febootstrap-install \
	febootstrap-minimize \
	febootstrap-to-initramfs \
	febootstrap-to-supermin
DISTCLEANFILES = $(bin_SCRIPTS)

febootstrap: febootstrap.sh
	rm -f $@
	cp $< $@-t
	chmod 0555 $@-t
	mv $@-t $@

febootstrap-run: febootstrap-run.sh
	rm -f $@
	cp $< $@-t
	chmod 0555 $@-t
	mv $@-t $@

febootstrap-install: febootstrap-install.sh
	rm -f $@
	cp $< $@-t
	chmod 0555 $@-t
	mv $@-t $@

febootstrap-minimize: febootstrap-minimize.sh
	rm -f $@
	cp $< $@-t
	chmod 0555 $@-t
	mv $@-t $@

febootstrap-to-initramfs: febootstrap-to-initramfs.sh
	rm -f $@
	cp $< $@-t
	chmod 0555 $@-t
	mv $@-t $@

febootstrap-to-supermin: febootstrap-to-supermin.sh
	rm -f $@
	cp $< $@-t
	chmod 0555 $@-t
	mv $@-t $@

man_MANS = \
	febootstrap.8 \
	febootstrap-run.8 \
	febootstrap-install.8 \
	febootstrap-minimize.8 \
	febootstrap-to-initramfs.8 \
	febootstrap-to-supermin.8

if HAVE_PERLDOC

febootstrap.8: febootstrap.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

febootstrap.txt: febootstrap.pod
	pod2text $< > $@

febootstrap-run.8: febootstrap-run.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

febootstrap-run.txt: febootstrap-run.pod
	pod2text $< > $@

febootstrap-install.8: febootstrap-install.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

febootstrap-install.txt: febootstrap-install.pod
	pod2text $< > $@

febootstrap-minimize.8: febootstrap-minimize.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

febootstrap-minimize.txt: febootstrap-minimize.pod
	pod2text $< > $@

febootstrap-to-initramfs.8: febootstrap-to-initramfs.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

febootstrap-to-initramfs.txt: febootstrap-to-initramfs.pod
	pod2text $< > $@

febootstrap-to-supermin.8: febootstrap-to-supermin.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

febootstrap-to-supermin.txt: febootstrap-to-supermin.pod
	pod2text $< > $@

endif

EXTRA_DIST = \
	fakechroot-2.8-relchroot.patch \
	fakechroot-svn-no-dup-envs.patch \
	febootstrap.8 febootstrap.txt febootstrap.pod \
	  febootstrap.sh \
	febootstrap-run.8 febootstrap-run.txt febootstrap-run.pod \
	  febootstrap-run.sh \
	febootstrap-install.8 febootstrap-install.txt febootstrap-install.pod \
	  febootstrap-install.sh \
	febootstrap-minimize.8 febootstrap-minimize.txt \
	  febootstrap-minimize.pod \
	  febootstrap-minimize.sh \
	febootstrap-to-initramfs.8 febootstrap-to-initramfs.txt \
	  febootstrap-to-initramfs.pod \
	  febootstrap-to-initramfs.sh \
	febootstrap-to-supermin.8 febootstrap-to-supermin.txt \
	  febootstrap-to-supermin.pod \
	  febootstrap-to-supermin.sh \
	m4/gnulib-cache.m4
