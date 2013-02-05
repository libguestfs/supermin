/* supermin-helper reimplementation in C.
 * Copyright (C) 2009-2013 Red Hat Inc.
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
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <assert.h>

#include "error.h"

#include "helper.h"

static FILE *pp = NULL;

/* This is the command we run to calculate the SHA.  Note that we sort
 * the rows first so that the checksum is roughly stable, since the
 * order that we output files might not be (eg. because we rely on the
 * ordering of readdir).  Uncomment the second line to see the output
 * before hashing.
 */
static const char *shacmd = "sort | sha256sum | awk '{print $1}'";
//static const char *shacmd = "sort | cat";

static void
checksum_start (const char *hostcpu, const char *appliance,
                const char *modpath, const char *initrd)
{
  pp = popen (shacmd, "w");
  if (pp == NULL)
    error (EXIT_FAILURE, errno, "popen: command failed: %s", shacmd);

  fprintf (pp, "%s %s %s %d\n",
           PACKAGE_STRING, hostcpu, modpath, geteuid ());
}

static void
checksum_end (void)
{
  if (pclose (pp) == -1)
    error (EXIT_FAILURE, errno, "pclose: command failed: %s", shacmd);
  pp = NULL;
}

static void
checksum_file_stat (const char *filename, const struct stat *statbuf)
{
  /* Publically writable directories (ie. /tmp) and special files
   * don't have stable times.  Since we only care about some
   * attributes of directories and special files, we vary the output
   * accordingly.
   */
  if (S_ISREG (statbuf->st_mode))
    fprintf (pp, "%s %ld %ld %d %d %" PRIu64 " %o\n",
             filename,
             (long) statbuf->st_ctime, (long) statbuf->st_mtime,
             statbuf->st_uid, statbuf->st_gid, (uint64_t) statbuf->st_size,
             statbuf->st_mode);
  else
    fprintf (pp, "%s %d %d %o\n",
             filename,
             statbuf->st_uid, statbuf->st_gid,
             statbuf->st_mode);
}

static void
checksum_file (const char *filename)
{
  struct stat statbuf;

  if (lstat (filename, &statbuf) == -1)
    error (EXIT_FAILURE, errno, "lstat: %s", filename);
  checksum_file_stat (filename, &statbuf);
}

static void
checksum_fts_entry (FTSENT *entry)
{
  if (entry->fts_info & FTS_NS || entry->fts_info & FTS_NSOK)
    checksum_file (entry->fts_path);
  else
    checksum_file_stat (entry->fts_path, entry->fts_statp);
}

static void
checksum_cpio_file (const char *cpio_file)
{
  checksum_file (cpio_file);
}

struct writer checksum_writer = {
  .wr_start = checksum_start,
  .wr_end = checksum_end,
  .wr_file = checksum_file,
  .wr_file_stat = checksum_file_stat,
  .wr_fts_entry = checksum_fts_entry,
  .wr_cpio_file = checksum_cpio_file,
};
