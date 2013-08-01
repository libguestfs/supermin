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
#include <fcntl.h>
#include <fnmatch.h>
#include <unistd.h>
#include <errno.h>
#include <sys/utsname.h>

#include "error.h"
#include "xvasprintf.h"
#include "full-write.h"

#include "helper.h"

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

/* Directory containing candidate kernels.  We could make this
 * configurable at some point.
 */
#define KERNELDIR "/boot"
#define MODULESDIR "/lib/modules"

static char* get_kernel_version (char* filename);
static const char *create_kernel_from_env (const char *hostcpu, const char *kernel, const char *kernel_env, const char *modpath_env);
static void copy_or_symlink_kernel (const char *from, const char *to);

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

  if (! isdir (modpath)) {
    char* path;
    char* version;
    path = xasprintf (KERNELDIR "/%s", kernel_name);
    if (!path) {
      perror ("xasprintf");
      exit (EXIT_FAILURE);
    }
    version = get_kernel_version (path);
    free (path);
    if (version != NULL) {
      free (modpath);
      modpath = xasprintf (MODULESDIR "/%s", version);
      free (version);
      if (!path) {
        perror ("xasprintf");
        exit (EXIT_FAILURE);
      }
    }
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
    free (modpath);
    return 1;
  }
  else {
    if (verbose)
      fprintf (stderr, "ignoring %s (no modpath %s)\n", kernel_name, modpath);
    free (modpath);
    return 0;
  }
}

/* Create the kernel.  This chooses an appropriate kernel and makes a
 * symlink to it (or copies it if --copy-kernel was passed).
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
  char *kernel_env = getenv ("SUPERMIN_KERNEL");
  if (kernel_env) {
    char *modpath_env = getenv ("SUPERMIN_MODULES");
    return create_kernel_from_env (hostcpu, kernel, kernel_env, modpath_env);
  }

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

  if (verbose)
    fprintf (stderr, "picked %s\n", candidates[0]);

  if (kernel) {
    /* Choose the first candidate. */
    char *tmp = xasprintf (KERNELDIR "/%s", candidates[0]);
    copy_or_symlink_kernel (tmp, kernel);
    free (tmp);
  }

  return get_modpath (candidates[0]);

  /* Print more diagnostics here than the old script did. */
 no_kernels:
  fprintf (stderr,
           "supermin-helper: failed to find a suitable kernel.\n"
           "I looked for kernels in " KERNELDIR " and modules in " MODULESDIR
           ".\n"
           "If this is a Xen guest, and you only have Xen domU kernels\n"
           "installed, try installing a fullvirt kernel (only for\n"
           "supermin use, you shouldn't boot the Xen guest with it).\n");
  exit (EXIT_FAILURE);
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
             "supermin-helper: using environment variable(s) SUPERMIN_* to\n"
             "select kernel %s", kernel_env);
    if (modpath_env)
      fprintf (stderr, " and module path %s", modpath_env);
    fprintf (stderr, "\n");
  }

  if (!isfile (kernel_env)) {
    fprintf (stderr,
             "supermin-helper: %s: not a regular file\n"
             "(what is $SUPERMIN_KERNEL set to?)\n", kernel_env);
    exit (EXIT_FAILURE);
  }

  if (!modpath_env) {
    /* Try to guess modpath from kernel path. */
    const char *p = strrchr (kernel_env, '/');
    if (p) p++; else p = kernel_env;

    /* NB: We need the extra test to ensure calling get_modpath is safe. */
    if (strncmp (p, "vmlinuz-", 8) != 0) {
      fprintf (stderr,
               "supermin-helper: cannot guess module path.\n"
               "Set $SUPERMIN_MODULES to the modules directory corresponding to\n"
               "kernel %s, or unset $SUPERMIN_KERNEL to autoselect a kernel.\n",
               kernel_env);
      exit (EXIT_FAILURE);
    }

    modpath_env = get_modpath (p);
  }

  if (!isdir (modpath_env)) {
    fprintf (stderr,
             "supermin-helper: %s: not a directory\n"
             "(what is $SUPERMIN_MODULES set to?)\n", modpath_env);
    exit (EXIT_FAILURE);
  }

  /* Create the symlink. */
  if (kernel)
    copy_or_symlink_kernel (kernel_env, kernel);

  return modpath_env;
}

static void
copy_or_symlink_kernel (const char *from, const char *to)
{
  int fd1, fd2;
  char buf[BUFSIZ];
  ssize_t r;

  if (verbose >= 2)
    fprintf (stderr, "%s kernel %s -> %s\n",
             !copy_kernel ? "symlink" : "copy", from, to);

  if (!copy_kernel) {
    if (symlink (from, to) == -1)
      error (EXIT_FAILURE, errno, "creating kernel symlink %s %s", from, to);
  }
  else {
    fd1 = open (from, O_RDONLY | O_CLOEXEC);
    if (fd1 == -1)
      error (EXIT_FAILURE, errno, "open: %s", from);

    fd2 = open (to, O_WRONLY|O_CREAT|O_NOCTTY|O_CLOEXEC, 0644);
    if (fd2 == -1)
      error (EXIT_FAILURE, errno, "open: %s", to);

    while ((r = read (fd1, buf, sizeof buf)) > 0) {
      if (full_write (fd2, buf, r) != r)
        error (EXIT_FAILURE, errno, "write: %s", to);
    }

    if (r == -1)
      error (EXIT_FAILURE, errno, "read: %s", from);

    if (close (fd1) == -1)
      error (EXIT_FAILURE, errno, "close: %s", from);

    if (close (fd2) == -1)
      error (EXIT_FAILURE, errno, "close: %s", to);
  }
}

/* Read an unsigned little endian short at a specified offset in a file.
 * Returns a non-negative int on success or -1 on failure.
 */
static int
read_leshort (FILE* fp, int offset)
{
  char buf[2];
  if (fseek (fp, offset, SEEK_SET) != 0 ||
      fread (buf, sizeof(char), 2, fp) != 2)
  {
    return -1;
  }
  return ((buf[1] & 0xFF) << 8) | (buf[0] & 0xFF);
}

/* Extract the kernel version from a Linux kernel file.
 * Returns a malloc'd string containing the version or NULL if the
 * file can't be read, is not a Linux kernel, or the version can't
 * be found.
 *
 * See ftp://ftp.astron.com/pub/file/file-<ver>.tar.gz
 * (file-<ver>/magic/Magdir/linux) for the rules used to find the
 * version number:
 *   514             string  HdrS     Linux kernel
 *   >518            leshort >0x1ff
 *   >>(526.s+0x200) string  >\0      version %s,
 *
 * Bugs: probably limited to x86 kernels.
 */
static char*
get_kernel_version (char* filename)
{
  FILE* fp;
  int size = 132;
  char buf[size];
  int offset;

  fp = fopen (filename, "rb");

  if (fseek (fp, 514, SEEK_SET) != 0 ||
      fgets (buf, size, fp) == NULL ||
      strncmp (buf, "HdrS", 4) != 0 ||
      read_leshort (fp, 518) < 0x1FF)
  {
    /* not a Linux kernel */
    fclose (fp);
    return NULL;
  }

  offset = read_leshort (fp, 526);
  if (offset == -1)
  {
    /* can't read version offset */
    fclose (fp);
    return NULL;
  }

  if (fseek (fp, offset + 0x200, SEEK_SET) != 0 ||
      fgets (buf, size, fp) == NULL)
  {
    /* can't read version string */
    fclose (fp);
    return NULL;
  }

  fclose (fp);

  buf[strcspn (buf, " \t\n")] = '\0';
  return strdup (buf);
}
