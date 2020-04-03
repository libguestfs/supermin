# supermin Makefile.am
# (C) Copyright 2013-2014 Red Hat Inc.
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

LOG_DRIVER = env $(SHELL) $(top_srcdir)/supermin-test-driver

EXTRA_DIST = \
	automake2junit.ml \
	$(TESTS)

TESTS = \
	test-basic.sh \
	test-execstack.sh \
	test-build-bash.sh \
	test-binaries-exist.sh \
	test-harder.sh \
	test-if-newer-ext2.sh

if NETWORK_TESTS
TESTS += \
	test-build-bash-network.sh \
	test-binaries-exist-network.sh \
	test-harder-network.sh
endif
