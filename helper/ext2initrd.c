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

/* ext2 requires a small initrd in order to boot.  This builds it. */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <assert.h>

#include "error.h"
#include "full-write.h"
#include "xalloc.h"
#include "xvasprintf.h"

#include "helper.h"
#include "ext2internal.h"

static void read_module_deps (const char *modpath);
static void free_module_deps (void);
static const char *get_module_dep (const char *);

/* The init binary. */
extern char _binary_init_start, _binary_init_end, _binary_init_size;

/* The list of modules (wildcards) we consider for inclusion in the
 * mini initrd.  Only what is needed in order to find a device with an
 * ext2 filesystem on it.
 */
static const char *kmods[] = {
  "ext2.ko",
  "virtio*.ko",
  "ide*.ko",
  "libata*.ko",
  "piix*.ko",
  "scsi_transport_spi.ko",
  "scsi_mod.ko",
  "sd_mod.ko",
  "sym53c8xx.ko",
  "ata_piix.ko",
  "sr_mod.ko",
  "mbcache.ko",
  "crc*.ko",
  "libcrc*.ko",
  NULL
};

void
ext2_make_initrd (const char *modpath, const char *initrd)
{
  char dir[] = "/tmp/ext2initrdXXXXXX";
  if (mkdtemp (dir) == NULL)
    error (EXIT_FAILURE, errno, "mkdtemp");

  char *cmd;
  int r;

  /* Copy kernel modules into tmpdir. */
  size_t n = strlen (modpath) + strlen (dir) + 64;
  size_t i;
  for (i = 0; kmods[i] != NULL; ++i)
    n += strlen (kmods[i]) + 16;
  cmd = malloc (n);
  /* "cd /" here is for virt-v2v.  It's cwd might not be accessible by
   * the current user (because it sometimes sets its own uid) and the
   * "find" command works by changing directory then changing back to
   * the cwd.  This results in a warning:
   *
   * find: failed to restore initial working directory: Permission denied
   *
   * Note this only works because "modpath" and temporary "dir" are
   * currently guaranteed to be absolute paths, hence assertion.
   */
  assert (modpath[0] == '/');
  sprintf (cmd, "cd / ; find '%s' ", modpath);
  for (i = 0; kmods[i] != NULL; ++i) {
    if (i > 0) strcat (cmd, "-o ");
    strcat (cmd, "-name '");
    strcat (cmd, kmods[i]);
    strcat (cmd, "' ");
  }
  strcat (cmd, "| xargs cp -t ");
  strcat (cmd, dir);
  if (verbose >= 2) fprintf (stderr, "%s\n", cmd);
  r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0)
    error (EXIT_FAILURE, 0, "ext2_make_initrd: copy kmods failed");
  free (cmd);

  /* The above command effectively gives us the final list of modules.
   * Calculate dependencies from modpath/modules.dep and write that
   * into the output.
   */
  read_module_deps (modpath);

  cmd = xasprintf ("tsort > %s/modules", dir);
  if (verbose >= 2) fprintf (stderr, "%s\n", cmd);
  FILE *pp = popen (cmd, "w");
  if (pp == NULL)
    error (EXIT_FAILURE, errno, "tsort: failed to create modules list");

  DIR *dr = opendir (dir);
  if (dr == NULL)
    error (EXIT_FAILURE, errno, "opendir: %s", dir);

  struct dirent *d;
  while ((errno = 0, d = readdir (dr)) != NULL) {
    size_t n = strlen (d->d_name);
    if (n >= 3 &&
        d->d_name[n-3] == '.' &&
        d->d_name[n-2] == 'k' &&
        d->d_name[n-1] == 'o') {
      const char *dep = get_module_dep (d->d_name);
      if (dep)
        /* Reversed so that tsort will print the final list in the
         * order that it has to be loaded.
         */
        fprintf (pp, "%s %s\n", dep, d->d_name);
      else
        /* No dependencies, just make it depend on itself so that
         * tsort prints it.
         */
        fprintf (pp, "%s %s\n", d->d_name, d->d_name);
    }
  }
  if (errno)
    error (EXIT_FAILURE, errno, "readdir: %s", dir);

  if (closedir (dr) == -1)
    error (EXIT_FAILURE, errno, "closedir: %s", dir);

  if (pclose (pp) == -1)
    error (EXIT_FAILURE, errno, "pclose: %s", cmd);

  free (cmd);
  free_module_deps ();

  /* Copy in the init program, linked into this program as a data blob. */
  char *init = xasprintf ("%s/init", dir);
  int fd = open (init, O_WRONLY|O_TRUNC|O_CREAT|O_NOCTTY, 0755);
  if (fd == -1)
    error (EXIT_FAILURE, errno, "open: %s", init);

  n = (size_t) &_binary_init_size;
  if (full_write (fd, &_binary_init_start, n) != n)
    error (EXIT_FAILURE, errno, "write: %s", init);

  if (close (fd) == -1)
    error (EXIT_FAILURE, errno, "close: %s", init);

  free (init);

  /* Build the cpio file. */
  cmd = xasprintf ("(cd %s && (echo . ; ls -1)"
                   " | cpio --quiet -o -H newc) > '%s'",
                   dir, initrd);
  if (verbose >= 2) fprintf (stderr, "%s\n", cmd);
  r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0)
    error (EXIT_FAILURE, 0, "ext2_make_initrd: cpio failed");
  free (cmd);

  /* Construction of 'dir' above ensures this is safe. */
  cmd = xasprintf ("rm -rf %s", dir);
  if (verbose >= 2) fprintf (stderr, "%s\n", cmd);
  system (cmd);
  free (cmd);
}

/* Module dependencies. */
struct moddep {
  struct moddep *next;
  char *name;
  char *dep;
};
struct moddep *moddeps = NULL;

static void add_module_dep (const char *name, const char *dep);

static void
free_module_deps (void)
{
  /* Short-lived program, don't bother to free it. */
  moddeps = NULL;
}

/* Read modules.dep into internal structure. */
static void
read_module_deps (const char *modpath)
{
  free_module_deps ();

  char *filename = xasprintf ("%s/modules.dep", modpath);
  FILE *fp = fopen (filename, "r");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "open: %s", modpath);

  char *line = NULL;
  size_t llen = 0;
  ssize_t len;
  while ((len = getline (&line, &llen, fp)) != -1) {
    if (len > 0 && line[len-1] == '\n')
      line[--len] = '\0';

    char *name = strtok (line, ": ");
    if (!name) continue;

    /* Only want the module basename, but keep the ".ko" extension. */
    char *p = strrchr (name, '/');
    if (p) name = p+1;

    char *dep;
    while ((dep = strtok (NULL, " ")) != NULL) {
      p = strrchr (dep, '/');
      if (p) dep = p+1;

      add_module_dep (name, dep);
    }
  }

  free (line);
  fclose (fp);
}

/* Module 'name' requires 'dep' to be loaded first. */
static void
add_module_dep (const char *name, const char *dep)
{
  struct moddep *m = xmalloc (sizeof *m);
  m->next = moddeps;
  moddeps = m;
  m->name = xstrdup (name);
  m->dep = xstrdup (dep);
}

static const char *
get_module_dep (const char *name)
{
  struct moddep *m;

  for (m = moddeps; m; m = m->next)
    if (strcmp (m->name, name) == 0)
      return m->dep;

  return NULL;
}
