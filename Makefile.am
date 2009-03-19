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

bin_SCRIPTS = febootstrap

febootstrap: febootstrap.sh
	rm -f $@
	cp $< $@-t
	chmod 0755 $@-t
	mv $@-t $@

man_MANS = febootstrap.8

if HAVE_PERLDOC
febootstrap.8: febootstrap.pod
	pod2man \
	  --section 8 \
	  -c "Virtualization Support" \
	  --release "$(PACKAGE_NAME)-$(PACKAGE_VERSION)" \
	  $< > $@

febootstrap.txt: febootstrap.pod
	pod2text $< > $@
endif

EXTRA_DIST = febootstrap.8 febootstrap.txt
