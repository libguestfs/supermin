#!/bin/sh -

if [ -z "$(ls gnulib 2>/dev/null)" ]
then
    git clone git://git.savannah.gnu.org/gnulib.git
fi

./gnulib/gnulib-tool --update

export AUTOMAKE='automake --foreign --add-missing'
autoreconf
./configure "$@"
