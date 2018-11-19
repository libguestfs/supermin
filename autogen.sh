#!/bin/bash -

set -e

# If the submodule is not initialized run bootstrap
if git submodule status .gnulib | grep -q '^-'; then
    ./bootstrap
fi

# If no arguments were specified and configure has run before, use the previous
# arguments
if test $# -eq 0 && test -x ./config.status; then
    ./config.status --recheck
else
    autoreconf -i
    ./configure "$@"
fi
