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
#include <fnmatch.h>
#include <unistd.h>
#include <errno.h>

#include "error.h"
#include "xvasprintf.h"

#include "helper.h"

/* Directory containing candidate kernels.  We could make this
 * configurable at some point.
 */
#define KERNELDIR "/boot"
#define MODULESDIR "/lib/modules"

static char *
get_modpath (const char *kernel_name)
{
  /* Ignore "vmlinuz-" at the beginning of the kernel name. */
  const char *version = &kernel_name[8];

  /* /lib/modules/<version> */
  char *modpath = xasprintf (MODULESDIR "/%s", version);
  if (!modpath) {
    perror ("xasprintf");
    exit (EXIT_FAILURE);
  }

  return modpath;
}

/* kernel_name is "vmlinuz-*".  Check if there is a corresponding
 * module path in /lib/modules.
 */
static int
has_modpath (const char *kernel_name)
{
  char *modpath = get_modpath (kernel_name);

  if (verbose)
    fprintf (stderr, "checking modpath %s is a directory\n", modpath);

  int r = isdir (modpath);

  if (r) {
    if (verbose)
      fprintf (stderr, "picked %s because modpath %s exists\n",
               kernel_name, modpath);
    free (modpath);
    return 1;
  }
  else {
    free (modpath);
    return 0;
  }
}

static const char *create_kernel_archlinux (const char *hostcpu, const char *kernel);
static const char *create_kernel_from_env (const char *hostcpu, const char *kernel, const char *kernel_env, const char *modpath_env);

/* Create the kernel.  This chooses an appropriate kernel and makes a
 * symlink to it.
 *
 * Look for the most recent kernel named vmlinuz-*.<arch>* which has a
 * corresponding directory in /lib/modules/. If the architecture is
 * x86, look for any x86 kernel.
 *
 * RHEL 5 didn't append the arch to the kernel name, so look for
 * kernels without arch second.
 *
 * If no suitable kernel can be found, exit with an error.
 *
 * This function returns the module path (ie. /lib/modules/<version>).
 */
const char *
create_kernel (const char *hostcpu, const char *kernel)
{
  /* Override kernel selection using environment variables? */
  char *kernel_env = getenv ("FEBOOTSTRAP_KERNEL");
  if (kernel_env) {
    char *modpath_env = getenv ("FEBOOTSTRAP_MODULES");
    return create_kernel_from_env (hostcpu, kernel, kernel_env, modpath_env);
  }

  /* In ArchLinux, kernel is always named /boot/vmlinuz26. */
  if (access ("/boot/vmlinuz26", F_OK) == 0)
    return create_kernel_archlinux (hostcpu, kernel);

  /* In original: ls -1dvr /boot/vmlinuz-*.$arch* 2>/dev/null | grep -v xen */
  const char *patt;
  if (hostcpu[0] == 'i' && hostcpu[2] == '8' && hostcpu[3] == '6' &&
      hostcpu[4] == '\0')
    patt = "vmlinuz-*.i?86*";
  else
    patt = xasprintf ("vmlinuz-*.%s*", hostcpu);

  char **all_files = read_dir (KERNELDIR);
  char **candidates;
  candidates = filter_fnmatch (all_files, patt, FNM_NOESCAPE);
  candidates = filter_notmatching_substring (candidates, "xen");
  candidates = filter (candidates, has_modpath);

  if (candidates[0] == NULL) {
    /* In original: ls -1dvr /boot/vmlinuz-* 2>/dev/null | grep -v xen */
    patt = "vmlinuz-*";
    candidates = filter_fnmatch (all_files, patt, FNM_NOESCAPE);
    candidates = filter_notmatching_substring (candidates, "xen");
    candidates = filter (candidates, has_modpath);

    if (candidates[0] == NULL)
      goto no_kernels;
  }

  sort (candidates, reverse_filevercmp);

  if (kernel) {
    /* Choose the first candidate. */
    char *tmp = xasprintf (KERNELDIR "/%s", candidates[0]);

    if (verbose >= 2)
      fprintf (stderr, "creating symlink %s -> %s\n", kernel, tmp);

    if (symlink (tmp, kernel) == -1)
      error (EXIT_FAILURE, errno, "symlink kernel");

    free (tmp);
  }

  return get_modpath (candidates[0]);

  /* Print more diagnostics here than the old script did. */
 no_kernels:
  fprintf (stderr,
           "febootstrap-supermin-helper: failed to find a suitable kernel.\n"
           "I looked for kernels in " KERNELDIR " and modules in " MODULESDIR
           ".\n"
           "If this is a Xen guest, and you only have Xen domU kernels\n"
           "installed, try installing a fullvirt kernel (only for\n"
           "febootstrap use, you shouldn't boot the Xen guest with it).\n");
  exit (EXIT_FAILURE);
}

/* In ArchLinux, kernel is always named /boot/vmlinuz26, and we have
 * to use the 'file' command to work out what version it is.
 */
static const char *
create_kernel_archlinux (const char *hostcpu, const char *kernel)
{
  const char *file_cmd = "file /boot/vmlinuz26 | awk '{print $9}'";
  FILE *pp;
  char modversion[256];
  char *modpath;
  size_t len;

  pp = popen (file_cmd, "r");
  if (pp == NULL) {
  error:
    fprintf (stderr, "febootstrap-supermin-helper: %s: command failed\n",
             file_cmd);
    exit (EXIT_FAILURE);
  }

  if (fgets (modversion, sizeof modversion, pp) == NULL)
    goto error;

  if (pclose (pp) == -1)
    goto error;

  /* Chomp final \n */
  len = strlen (modversion);
  if (len > 0 && modversion[len-1] == '\n') {
    modversion[len-1] = '\0';
    len--;
  }

  /* Generate module path. */
  modpath = xasprintf (MODULESDIR "/%s", modversion);

  /* Check module path is a directory. */
  if (!isdir (modpath)) {
    fprintf (stderr, "febootstrap-supermin-helper: /boot/vmlinuz26 kernel exists but %s is not a valid module path\n",
             modpath);
    exit (EXIT_FAILURE);
  }

  if (kernel) {
    /* Symlink from kernel to /boot/vmlinuz26. */
    if (symlink ("/boot/vmlinuz26", kernel) == -1)
      error (EXIT_FAILURE, errno, "symlink kernel");
  }

  /* Return module path. */
  return modpath;
}

/* Select the kernel from environment variables set by the user.
 * modpath_env may be NULL, in which case we attempt to work it out
 * from kernel_env.
 */
static const char *
create_kernel_from_env (const char *hostcpu, const char *kernel,
                        const char *kernel_env, const char *modpath_env)
{
  if (verbose) {
    fprintf (stderr,
             "febootstrap-supermin-helper: using environment variable(s) FEBOOTSTRAP_* to\n"
             "select kernel %s", kernel_env);
    if (modpath_env)
      fprintf (stderr, " and module path %s", modpath_env);
    fprintf (stderr, "\n");
  }

  if (!isfile (kernel_env)) {
    fprintf (stderr,
             "febootstrap-supermin-helper: %s: not a regular file\n"
             "(what is $FEBOOTSTRAP_KERNEL set to?)\n", kernel_env);
    exit (EXIT_FAILURE);
  }

  if (!modpath_env) {
    /* Try to guess modpath from kernel path. */
    const char *p = strrchr (kernel_env, '/');
    if (p) p++; else p = kernel_env;

    /* NB: We need the extra test to ensure calling get_modpath is safe. */
    if (strncmp (p, "vmlinuz-", 8) != 0) {
      fprintf (stderr,
               "febootstrap-supermin-helper: cannot guess module path.\n"
               "Set $FEBOOTSTRAP_MODULES to the modules directory corresponding to\n"
               "kernel %s, or unset $FEBOOTSTRAP_KERNEL to autoselect a kernel.\n",
               kernel_env);
      exit (EXIT_FAILURE);
    }

    modpath_env = get_modpath (p);
  }

  if (!isdir (modpath_env)) {
    fprintf (stderr,
             "febootstrap-supermin-helper: %s: not a directory\n"
             "(what is $FEBOOTSTRAP_MODULES set to?)\n", modpath_env);
    exit (EXIT_FAILURE);
  }

  /* Create the symlink. */
  if (kernel) {
    if (verbose >= 2)
      fprintf (stderr, "creating symlink %s -> %s\n", kernel_env, kernel);

    if (symlink (kernel_env, kernel) == -1)
      error (EXIT_FAILURE, errno, "symlink kernel");
  }

  return modpath_env;
}
