# febootstrap Makefile.am
# (C) Copyright 2009 Red Hat Inc.
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

SUBDIRS = examples

bin_SCRIPTS = \
	febootstrap \
	febootstrap-minimize \
	febootstrap-to-initramfs

febootstrap: febootstrap.sh
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

man_MANS = \
	febootstrap.8 \
	febootstrap-minimize.8 \
	febootstrap-to-initramfs.8

if HAVE_PERLDOC

febootstrap.8: febootstrap.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

febootstrap.txt: febootstrap.pod
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

endif

EXTRA_DIST = \
	fakechroot-2.8-relchroot.patch \
	febootstrap.8 febootstrap.txt febootstrap.pod \
	febootstrap-minimize.8 febootstrap-minimize.txt \
	  febootstrap-minimize.pod \
	febootstrap-to-initramfs.8 febootstrap-to-initramfs.txt \
	  febootstrap-to-initramfs.pod \
	febootstrap.sh febootstrap-to-initramfs.sh
