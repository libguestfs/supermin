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

/* This very minimal init "script" goes in the mini-initrd used to
 * boot the ext2-based appliance.  Note we have no shell, so we cannot
 * use system(3) to run external commands.  In fact, we don't have
 * very much at all, except this program, insmod.static, and some
 * kernel modules.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>

/* Leave this enabled for now.  When we get more confident in the boot
 * process we can turn this off or make it configurable.
 */
#define verbose 1

static void print_uptime (void);
static void insmod (const char *filename);

static char line[1024];

int
main ()
{
  print_uptime ();
  fprintf (stderr, "febootstrap: ext2 mini initrd starting up\n");

  /* Create some fixed directories. */
  mkdir ("/dev", 0755);
  mkdir ("/root", 0755);
  mkdir ("/sys", 0755);

  /* Mount /sys. */
  if (verbose)
    fprintf (stderr, "febootstrap: mounting /sys\n");
  if (mount ("sysfs", "/sys", "sysfs", 0, "") == -1) {
    perror ("mount: /sys");
    exit (EXIT_FAILURE);
  }

  /* A perennial problem is that /sbin/insmod.static is not
   * executable.  Just make it executable.  It's easier than fixing
   * everyone's distro.
   */
  chmod ("/sbin/insmod.static", 0755);

  FILE *fp = fopen ("/modules", "r");
  if (fp == NULL) {
    perror ("fopen: /modules");
    exit (EXIT_FAILURE);
  }
  while (fgets (line, sizeof line, fp)) {
    size_t n = strlen (line);
    if (n > 0 && line[n-1] == '\n')
      line[--n] = '\0';
    insmod (line);
  }
  fclose (fp);

  /* Look for the ext2 filesystem device.  It's always the last
   * one that was added.
   * XXX More than 25 devices?
   */
  char path[] = "/sys/block/xdx/dev";
  char class[3] = { 'v', 's', 'h' };
  size_t i, j;
  fp = NULL;
  for (i = 0; i < sizeof class; ++i) {
    for (j = 'z'; j >= 'a'; --j) {
      path[11] = class[i];
      path[13] = j;
      fp = fopen (path, "r");
      if (fp != NULL)
        goto found;
    }
  }
  fprintf (stderr,
           "febootstrap: no ext2 root device found\n"
           "Please include FULL verbose output in your bug report.\n");
  exit (EXIT_FAILURE);

 found:
  if (verbose)
    fprintf (stderr, "febootstrap: picked %s as root device\n", path);

  fgets (line, sizeof line, fp);
  int major = atoi (line);
  char *p = line + strcspn (line, ":") + 1;
  int minor = atoi (p);

  fclose (fp);
  if (umount ("/sys") == -1) {
    perror ("umount: /sys");
    exit (EXIT_FAILURE);
  }

  if (verbose)
    fprintf (stderr, "febootstrap: creating /dev/root as block special %d:%d\n",
             major, minor);

  if (mknod ("/dev/root", S_IFBLK|0700, makedev (major, minor)) == -1) {
    perror ("mknod: /dev/root");
    exit (EXIT_FAILURE);
  }

  /* Mount new root and chroot to it. */
  if (verbose)
    fprintf (stderr, "febootstrap: mounting new root on /root\n");
  if (mount ("/dev/root", "/root", "ext2", MS_NOATIME, "") == -1) {
    perror ("mount: /root");
    exit (EXIT_FAILURE);
  }

  /* Note that pivot_root won't work.  See the note in
   * Documentation/filesystems/ramfs-rootfs-initramfs.txt
   * We could remove the old initramfs files, but let's not bother.
   */
  if (verbose)
    fprintf (stderr, "febootstrap: chroot\n");

  if (chroot ("/root") == -1) {
    perror ("chroot: /root");
    exit (EXIT_FAILURE);
  }

  chdir ("/");

  /* Run /init from ext2 filesystem. */
  print_uptime ();
  execl ("/init", "init", NULL);
  perror ("execl: /init");
  exit (EXIT_FAILURE);
}

static void
insmod (const char *filename)
{
  if (verbose)
    fprintf (stderr, "febootstrap: insmod %s\n", filename);

  pid_t pid = fork ();
  if (pid == -1) {
    perror ("insmod: fork");
    exit (EXIT_FAILURE);
  }

  if (pid == 0) { /* Child. */
    execl ("/insmod.static", "insmod.static", filename, NULL);
    perror ("insmod: execl");
    _exit (EXIT_FAILURE);
  }

  /* Parent. */
  int status;
  if (wait (&status) == -1 ||
      WEXITSTATUS (status) != 0)
    perror ("insmod: wait");
    /* but ignore the error, some will be because the device is not found */
}

/* Print contents of /proc/uptime. */
static void
print_uptime (void)
{
  FILE *fp = fopen ("/proc/uptime", "r");
  if (fp == NULL) {
    perror ("/proc/uptime");
    return;
  }

  fgets (line, sizeof line, fp);
  fclose (fp);

  fprintf (stderr, "febootstrap: uptime: %s", line);
}
