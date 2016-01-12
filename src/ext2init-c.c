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

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/memory.h>

/* The init binary.
 * See: bin2s.pl, init.c.
 */
extern uint8_t _binary_init_start, _binary_init_end;

value
supermin_binary_init (value unitv)
{
  CAMLparam1 (unitv);
  CAMLlocal1 (sv);
  size_t n = &_binary_init_end - &_binary_init_start;

  sv = caml_alloc_string (n);
  memcpy (String_val (sv), &_binary_init_start, n);

  CAMLreturn (sv);
}
