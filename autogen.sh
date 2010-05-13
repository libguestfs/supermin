#!/bin/sh -

if [ -d ../gnulib ]; then
    ../gnulib/gnulib-tool --update
fi

export AUTOMAKE='automake --foreign --add-missing'
autoreconf
./configure "$@"
