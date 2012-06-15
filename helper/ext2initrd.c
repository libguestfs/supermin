/* febootstrap-supermin-helper reimplementation in C.
 * Copyright (C) 2009-2012 Red Hat Inc.
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
#include <fnmatch.h>

#include "error.h"
#include "full-write.h"
#include "xalloc.h"
#include "xvasprintf.h"

#include "helper.h"
#include "ext2internal.h"

static void read_module_deps (const char *modpath);
static void free_module_deps (void);
static void add_module_dep (const char *name, const char *dep);
static struct module * add_module (const char *name);
static struct module * find_module (const char *name);
static void print_module_load_order (FILE *f, FILE *pp, struct module *m);

/* The init binary. */
extern char _binary_init_start, _binary_init_end, _binary_init_size;

/* The list of modules (wildcards) we consider for inclusion in the
 * mini initrd.  Only what is needed in order to find a device with an
 * ext2 filesystem on it.
 */
static const char *kmods[] = {
  "ext2.ko*",
  "ext4.ko*", /* CONFIG_EXT4_USE_FOR_EXT23=y option might be set */
  "virtio*.ko*",
  "ide*.ko*",
  "libata*.ko*",
  "piix*.ko*",
  "scsi_transport_spi.ko*",
  "scsi_mod.ko*",
  "sd_mod.ko*",
  "sym53c8xx.ko*",
  "ata_piix.ko*",
  "sr_mod.ko*",
  "mbcache.ko*",
  "crc*.ko*",
  "libcrc*.ko*",
  "ibmvscsic.ko*",
  NULL
};

/* Module dependencies. */
struct module {
  struct module *next;
  struct moddep *deps;
  char *name;
  int visited;
};
struct module *modules = NULL;

struct moddep {
  struct moddep *next;
  struct module *dep;
};

void
ext2_make_initrd (const char *modpath, const char *initrd)
{
  char dir[] = "/tmp/ext2initrdXXXXXX";
  if (mkdtemp (dir) == NULL)
    error (EXIT_FAILURE, errno, "mkdtemp");

  read_module_deps (modpath);
  add_module ("");
  int i;
  struct module *m;
  for (i = 0; kmods[i] != NULL; ++i) {
    for (m = modules; m; m = m->next) {
      char *n = strrchr (m->name, '/');
      if (n)
        n += 1;
      else
        n = m->name;
      if (fnmatch (kmods[i], n, FNM_PATHNAME) == 0) {
        if (verbose >= 2)
          fprintf (stderr, "Adding top-level dependency %s (%s)\n", m->name, kmods[i]);
        add_module_dep ("", m->name);
      }
    }
  }

  char *cmd = xasprintf ("cd %s; xargs cp -t %s", modpath, dir);
  char *outfile = xasprintf ("%s/modules", dir);
  if (verbose >= 2) fprintf (stderr, "writing to %s\n", cmd);

  FILE *f = fopen (outfile, "w");
  if (f == NULL)
    error (EXIT_FAILURE, errno, "failed to create modules list (%s)", outfile);
  free (outfile);
  FILE *pp = popen (cmd, "w");
  if (pp == NULL)
    error (EXIT_FAILURE, errno, "failed to create pipe (%s)", cmd);

  /* The "pseudo" module depends on all modules matched by the contents of kmods */
  struct module *pseudo = find_module ("");
  print_module_load_order (pp, f, pseudo);
  fclose (pp);
  pclose (f);

  free (cmd);
  free_module_deps ();

  /* Copy in the init program, linked into this program as a data blob. */
  char *init = xasprintf ("%s/init", dir);
  int fd = open (init, O_WRONLY|O_TRUNC|O_CREAT|O_NOCTTY, 0755);
  if (fd == -1)
    error (EXIT_FAILURE, errno, "open: %s", init);

  size_t n = (size_t) &_binary_init_size;
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
  int r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0)
    error (EXIT_FAILURE, 0, "ext2_make_initrd: cpio failed");
  free (cmd);

  /* Construction of 'dir' above ensures this is safe. */
  cmd = xasprintf ("rm -rf %s", dir);
  if (verbose >= 2) fprintf (stderr, "%s\n", cmd);
  system (cmd);
  free (cmd);
}

static void
free_module_deps (void)
{
  /* Short-lived program, don't bother to free it. */
  modules = NULL;
}

/* Read modules.dep into internal structure. */
static void
read_module_deps (const char *modpath)
{
  free_module_deps ();

  char *filename = xasprintf ("%s/modules.dep", modpath);
  FILE *fp = fopen (filename, "r");
  free (filename);
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "open: %s/modules.dep", modpath);

  char *line = NULL;
  size_t llen = 0;
  ssize_t len;
  while ((len = getline (&line, &llen, fp)) != -1) {
    if (len > 0 && line[len-1] == '\n')
      line[--len] = '\0';

    char *name = strtok (line, ": ");
    if (!name) continue;

    add_module (name);
    char *dep;
    while ((dep = strtok (NULL, " ")) != NULL) {
      add_module_dep (name, dep);
    }
  }

  free (line);
  fclose (fp);
}

static struct module *
add_module (const char *name)
{
  struct module *m = find_module (name);
  if (m)
    return m;
  m = xmalloc (sizeof *m);
  m->name = xstrdup (name);
  m->deps = NULL;
  m->next = modules;
  m->visited = 0;
  modules = m;
  return m;
}

static struct module *
find_module (const char *name)
{
  struct module *m;
  for (m = modules; m; m = m->next) {
    if (strcmp (name, m->name) == 0)
      break;
  }
  return m;
}

/* Module 'name' requires 'dep' to be loaded first. */
static void
add_module_dep (const char *name, const char *dep)
{
  if (verbose >= 2) fprintf (stderr, "add_module_dep %s: %s\n", name, dep);
  struct module *m1 = add_module (name);
  struct module *m2 = add_module (dep);
  struct moddep *d;
  for (d = m1->deps; d; d = d->next) {
    if (d->dep == m2)
      return;
  }
  d = xmalloc (sizeof *d);
  d->next = m1->deps;
  d->dep = m2;
  m1->deps = d;
  return;
}

/* DFS on the dependency graph */
static void
print_module_load_order (FILE *pipe, FILE *list, struct module *m)
{
  if (m->visited)
    return;

  struct moddep *d;
  for (d = m->deps; d; d = d->next)
    print_module_load_order (pipe, list, d->dep);

  if (m->name[0] == 0)
    return;

  char *basename = strrchr (m->name, '/');
  if (basename)
    ++basename;
  else
    basename = m->name;

  fputs (m->name, pipe);
  fputc ('\n', pipe);
  fputs (basename, list);
  fputc ('\n', list);
  m->visited = 1;

  if (verbose >= 2)
    fprintf (stderr, "print_module_load_order: %s %s\n", m->name, basename);
}
