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
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <fnmatch.h>
#include <sys/stat.h>
#include <assert.h>

#include "error.h"
#include "fts_.h"
#include "xalloc.h"
#include "xvasprintf.h"

#include "helper.h"

static void iterate_inputs (char **inputs, int nr_inputs, struct writer *);
static void iterate_input_directory (const char *dirname, int dirfd, struct writer *);
static void add_kernel_modules (const char *whitelist, const char *modpath, struct writer *);
static void add_hostfiles (const char *hostfiles_file, struct writer *);

/* Create the appliance.
 *
 * The initrd consists of these components concatenated together:
 *
 * (1) The base skeleton appliance that we constructed at build time.
 *     format = plain cpio
 * (2) The host files which match wildcards in *.supermin.hostfiles.
 *     input format = plain text, output format = plain cpio
 * (3) The modules from modpath which are on the module whitelist.
 *     output format = plain cpio
 *
 * The original shell script used the external cpio program to create
 * parts (2) and (3), but we have decided it's going to be faster if
 * we just write out the data outselves.  The reasons are that
 * external cpio is slow (particularly when used with SELinux because
 * it does 512 byte reads), and the format that we're writing is
 * narrow and well understood, because we only care that the Linux
 * kernel can read it.
 *
 * This version contains some improvements over the C version written
 * for libguestfs, in that we can have multiple base images (or
 * hostfiles) or use a directory to store these files.
 */
void
create_appliance (const char *hostcpu,
                  char **inputs, int nr_inputs,
                  const char *whitelist,
                  const char *modpath,
                  const char *initrd,
                  const char *appliance,
                  struct writer *writer)
{
  writer->wr_start (hostcpu, appliance, modpath, initrd);

  iterate_inputs (inputs, nr_inputs, writer);

  writer->wr_file ("/lib/modules");
  /* Kernel modules (3). */
  add_kernel_modules (whitelist, modpath, writer);

  writer->wr_end ();
}

/* Iterate over the inputs to find out what they are, visiting
 * directories if specified.
 */
static void
iterate_inputs (char **inputs, int nr_inputs, struct writer *writer)
{
  int i;
  for (i = 0; i < nr_inputs; ++i) {
    if (verbose)
      print_timestamped_message ("visiting %s", inputs[i]);

    int fd = open (inputs[i], O_RDONLY);
    if (fd == -1)
      error (EXIT_FAILURE, errno, "open: %s", inputs[i]);

    struct stat statbuf;
    if (fstat (fd, &statbuf) == -1)
      error (EXIT_FAILURE, errno, "fstat: %s", inputs[i]);

    /* Directory? */
    if (S_ISDIR (statbuf.st_mode))
      iterate_input_directory (inputs[i], fd, writer);
    else if (S_ISREG (statbuf.st_mode)) {
      /* Is it a cpio file? */
      char buf[6];
      if (read (fd, buf, 6) == 6 && memcmp (buf, "070701", 6) == 0)
        /* Yes, a cpio file.  This is a skeleton appliance, case (1). */
        writer->wr_cpio_file (inputs[i]);
      else
        /* No, must be hostfiles, case (2). */
        add_hostfiles (inputs[i], writer);
    }
    else
      error (EXIT_FAILURE, 0, "%s: input is not a regular file or directory",
             inputs[i]);

    close (fd);
  }
}

static int
string_compare (const void *p1, const void *p2)
{
  return strcmp (* (char * const *) p1, * (char * const *) p2);
}

static void
iterate_input_directory (const char *dirname, int dirfd, struct writer *writer)
{
  DIR *dir = fdopendir (dirfd);
  if (dir == NULL)
    error (EXIT_FAILURE, errno, "fdopendir: %s", dirname);

  char **entries = NULL;
  size_t nr_entries = 0, nr_alloc = 0;

  struct dirent *d;
  while ((errno = 0, d = readdir (dir)) != NULL) {
    if (d->d_name[0] == '.') /* ignore ., .. and any hidden files. */
      continue;

    /* Ignore *~ files created by editors. */
    size_t len = strlen (d->d_name);
    if (len > 0 && d->d_name[len-1] == '~')
      continue;

    add_string (&entries, &nr_entries, &nr_alloc, d->d_name);
  }

  if (errno != 0)
    error (EXIT_FAILURE, errno, "readdir: %s", dirname);

  if (closedir (dir) == -1)
    error (EXIT_FAILURE, errno, "closedir: %s", dirname);

  add_string (&entries, &nr_entries, &nr_alloc, NULL);

  /* Visit directory entries in order.  In febootstrap <= 2.8 we
   * didn't impose any order, but that led to some difficult
   * heisenbugs.
   */
  sort (entries, string_compare);

  char path[PATH_MAX];
  strcpy (path, dirname);
  size_t len = strlen (dirname);
  path[len++] = '/';

  char *inputs[] = { path };

  size_t i;
  for (i = 0; entries[i] != NULL; ++i) {
    strcpy (&path[len], entries[i]);
    iterate_inputs (inputs, 1, writer);
  }
}

/* Copy kernel modules.
 *
 * Find every file under modpath.
 *
 * Exclude all *.ko files, *except* ones which match names in
 * the whitelist (which may contain wildcards).  Include all
 * other files.
 *
 * Add chosen files to the output.
 *
 * whitelist_file may be NULL, to include ALL kernel modules.
 */
static void
add_kernel_modules (const char *whitelist_file, const char *modpath,
                    struct writer *writer)
{
  if (verbose)
    print_timestamped_message ("adding kernel modules");

  char **whitelist = NULL;
  if (whitelist_file != NULL)
    whitelist = load_file (whitelist_file);

  char *paths[2] = { (char *) modpath, NULL };
  FTS *fts = fts_open (paths, FTS_COMFOLLOW|FTS_PHYSICAL, NULL);
  if (fts == NULL)
    error (EXIT_FAILURE, errno, "add_kernel_modules: fts_open: %s", modpath);

  for (;;) {
    errno = 0;
    FTSENT *entry = fts_read (fts);
    if (entry == NULL && errno != 0)
      error (EXIT_FAILURE, errno, "add_kernel_modules: fts_read: %s", modpath);
    if (entry == NULL)
      break;

    /* Ignore directories being visited in post-order. */
    if (entry->fts_info & FTS_DP)
      continue;

    /* Is it a *.ko file? */
    if (entry->fts_namelen >= 3 &&
        entry->fts_name[entry->fts_namelen-3] == '.' &&
        entry->fts_name[entry->fts_namelen-2] == 'k' &&
        entry->fts_name[entry->fts_namelen-1] == 'o') {
      if (whitelist) {
        /* Is it a *.ko file which is on the whitelist? */
        size_t j;
        for (j = 0; whitelist[j] != NULL; ++j) {
          int r;
          r = fnmatch (whitelist[j], entry->fts_name, 0);
          if (r == 0) {
            /* It's on the whitelist, so include it. */
            if (verbose >= 2)
              fprintf (stderr, "including kernel module %s (matches whitelist entry %s)\n",
                       entry->fts_name, whitelist[j]);
            writer->wr_fts_entry (entry);
            break;
          } else if (r != FNM_NOMATCH)
            error (EXIT_FAILURE, 0, "internal error: fnmatch ('%s', '%s', %d) returned unexpected non-zero value %d\n",
                   whitelist[j], entry->fts_name, 0, r);
        } /* for (j) */
      } else { /* whitelist == NULL, always include */
        if (verbose >= 2)
          fprintf (stderr, "including kernel module %s\n", entry->fts_name);
        writer->wr_fts_entry (entry);
      }
    } else
      /* It's some other sort of file, or a directory, always include. */
      writer->wr_fts_entry (entry);
  }

  if (fts_close (fts) == -1)
    error (EXIT_FAILURE, errno, "add_kernel_modules: fts_close: %s", modpath);
}

/* Copy the host files.
 *
 * Read the list of entries in hostfiles (which may contain
 * wildcards).  Look them up in the filesystem, and add those files
 * that exist.  Ignore any files that don't exist or are not readable.
 */
static void
add_hostfiles (const char *hostfiles_file, struct writer *writer)
{
  char **hostfiles = load_file (hostfiles_file);

  /* Hostfiles list can contain "." before each path - ignore it.
   * It also contains each directory name before we enter it.  But
   * we don't read that until we see a wildcard for that directory.
   */
  size_t i, j;
  for (i = 0; hostfiles[i] != NULL; ++i) {
    char *hostfile = hostfiles[i];
    if (hostfile[0] == '.')
      hostfile++;

    struct stat statbuf;

    /* Is it a wildcard? */
    if (strchr (hostfile, '*') || strchr (hostfile, '?')) {
      char *dirname = xstrdup (hostfile);
      char *patt = strrchr (dirname, '/');
      assert (patt);
      *patt++ = '\0';

      char **files = read_dir (dirname);
      files = filter_fnmatch (files, patt, FNM_NOESCAPE);

      /* Add matching files. */
      for (j = 0; files[j] != NULL; ++j) {
        char *tmp = xasprintf ("%s/%s", dirname, files[j]);

        if (verbose >= 2)
          fprintf (stderr, "including host file %s (matches %s)\n", tmp, patt);

        writer->wr_file (tmp);

        free (tmp);
      }
    }
    /* Else does this file/directory/whatever exist? */
    else if (lstat (hostfile, &statbuf) == 0) {
      if (verbose >= 2)
        fprintf (stderr, "including host file %s (directly referenced)\n",
                 hostfile);

      writer->wr_file_stat (hostfile, &statbuf);
    } /* Ignore files that don't exist. */
  }
}
