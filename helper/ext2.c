/* febootstrap-supermin-helper reimplementation in C.
 * Copyright (C) 2009-2010 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <assert.h>

#include "error.h"
#include "fts_.h"

#include "helper.h"

static void
ext2_start (const char *appliance,
            const char *modpath, const char *initrd)
{
  abort ();
}

struct writer ext2_writer = {
  .wr_start = ext2_start,
  /* .wr_end = ,
  .wr_file = ,
  .wr_file_stat = ,
  .wr_fts_entry = ,
  .wr_cpio_file = , */
};
