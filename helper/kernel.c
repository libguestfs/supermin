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
  char **all_files = read_dir (KERNELDIR);

  /* In original: ls -1dvr /boot/vmlinuz-*.$arch* 2>/dev/null | grep -v xen */
  const char *patt;
  if (hostcpu[0] == 'i' && hostcpu[2] == '8' && hostcpu[3] == '6' &&
      hostcpu[4] == '\0')
    patt = "vmlinuz-*.i?86*";
  else
    patt = xasprintf ("vmlinuz-*.%s*", hostcpu);

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
