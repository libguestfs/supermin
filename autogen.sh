#!/bin/sh -

./gnulib/gnulib-tool --update

export AUTOMAKE='automake --foreign --add-missing'
autoreconf
./configure "$@"
