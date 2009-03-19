#!/bin/sh -

export AUTOMAKE='automake --foreign --add-missing'
autoreconf
./configure "$@"
