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
#include <limits.h>
#include <errno.h>

#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

value
supermin_realpath (value pathv)
{
  CAMLparam1 (pathv);
  CAMLlocal1 (rv);
  char *r;

  r = realpath (String_val (pathv), NULL);
  if (r == NULL)
    unix_error (errno, (char *) "realpath", pathv);

  rv = caml_copy_string (r);
  free (r);
  CAMLreturn (rv);
}
