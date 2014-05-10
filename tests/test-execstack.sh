#!/bin/bash -
# supermin
# (C) Copyright 2014 Red Hat Inc.
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

set -e

if [ -n "$SKIP_TEST_EXECSTACK" ]; then
    echo "$0: test skipped because SKIP_TEST_EXECSTACK is set."
    exit 77
fi

if scanelf --help >/dev/null 2>&1; then
    echo "using scanelf"
    scanelf -e ../src/supermin
    test `scanelf -qe ../src/supermin | wc -l` -eq 0
elif readelf --help >/dev/null 2>&1; then
    echo "using readelf"
    readelf -lW ../src/supermin | grep GNU_STACK
    ! readelf -lW ../src/supermin | grep GNU_STACK | grep 'E ' >/dev/null 2>&1
else
    echo "$0: test skipped because none of the following tools is installed: scanelf, readelf"
    exit 77
fi
