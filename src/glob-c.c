/* supermin 5
 * Copyright (C) 2009-2014 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdlib.h>
#include <string.h>
#include <glob.h>
#include <assert.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

/* NB: These flags must appear in the same order as glob.ml */
static int flags[] = {
  GLOB_ERR,
  GLOB_MARK,
  GLOB_NOSORT,
  GLOB_NOCHECK,
  GLOB_NOESCAPE,
  GLOB_PERIOD,
};

value
supermin_glob (value patternv, value flagsv)
{
  CAMLparam2 (patternv, flagsv);
  CAMLlocal2 (rv, sv);
  int f = 0, r;
  size_t i;
  glob_t g;

  memset (&g, 0, sizeof g);

  /* Convert flags to bitmask. */
  while (flagsv != Val_int (0)) {
    f |= flags[Int_val (Field (flagsv, 0))];
    flagsv = Field (flagsv, 1);
  }

  r = glob (String_val (patternv), f, NULL, &g);

  if (r == 0 || r == GLOB_NOMATCH) {
    if (r == GLOB_NOMATCH)
      assert (g.gl_pathc == 0);

    rv = caml_alloc (g.gl_pathc, 0);
    for (i = 0; i < g.gl_pathc; ++i) {
      sv = caml_copy_string (g.gl_pathv[i]);
      Store_field (rv, i, sv);
    }

    globfree (&g);

    CAMLreturn (rv);
  }

  /* An error occurred. */
  globfree (&g);

  if (r == GLOB_NOSPACE)
    caml_raise_out_of_memory ();
  else if (r == GLOB_ABORTED)
    caml_failwith ("glob: read error");
  else
    caml_failwith ("glob: unknown error");
}
