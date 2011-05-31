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
 * very much at all, except this program, and some kernel modules.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <asm/unistd.h>

extern long init_module (void *, unsigned long, const char *);

/* Leave this enabled for now.  When we get more confident in the boot
 * process we can turn this off or make it configurable.
 */
#define verbose 1

static void mount_proc (void);
static void print_uptime (void);
static void insmod (const char *filename);
static void show_directory (const char *dir);

static char line[1024];

int
main ()
{
  mount_proc ();

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

  FILE *fp = fopen ("/modules", "r");
  if (fp == NULL) {
    perror ("fopen: /modules");
    exit (EXIT_FAILURE);
  }
  while (fgets (line, sizeof line, fp)) {
    size_t n = strlen (line);
    if (n > 0 && line[n-1] == '\n')
      line[--n] = '\0';

    /* XXX Because of the way we construct the module list, the
     * "modules" file can contain non-existent modules.  Ignore those
     * for now.  Really we should add them as missing dependencies.
     * See ext2initrd.c:ext2_make_initrd().
     */
    if (access (line, R_OK) == 0)
      insmod (line);
    else
      fprintf (stderr, "skipped %s, module is missing\n", line);
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

  /* /init failed to execute, but why?  Before we ditch, print some
   * debug.  Although we have a full appliance, the fact that /init
   * failed to run means we may not be able to run any commands.
   */
  show_directory ("/");
  show_directory ("/bin");
  show_directory ("/lib");
  show_directory ("/lib64");
  fflush (stderr);

  exit (EXIT_FAILURE);
}

static void
insmod (const char *filename)
{
  if (verbose)
    fprintf (stderr, "febootstrap: internal insmod %s\n", filename);

  int fd = open (filename, O_RDONLY);
  if (fd == -1) {
    fprintf (stderr, "insmod: open: %s: %m\n", filename);
    exit (EXIT_FAILURE);
  }
  struct stat st;
  if (fstat (fd, &st) == -1) {
    perror ("insmod: fstat");
    exit (EXIT_FAILURE);
  }
  char buf[st.st_size];
  long offset = 0;
  do {
    long rc = read (fd, buf + offset, st.st_size - offset);
    if (rc == -1) {
      perror ("insmod: read");
      exit (EXIT_FAILURE);
    }
    offset += rc;
  } while (offset < st.st_size);
  close (fd);

  if (init_module (buf, st.st_size, "") != 0) {
    fprintf (stderr, "insmod: init_module: %s: %m\n", filename);
    /* However ignore the error because this can just happen because
     * of a missing device.
     */
  }
}

/* Mount /proc unless it's mounted already. */
static void
mount_proc (void)
{
  if (access ("/proc/uptime", R_OK) == -1) {
    mkdir ("/proc", 0755);

    if (verbose)
      fprintf (stderr, "febootstrap: mounting /proc\n");

    if (mount ("proc", "/proc", "proc", 0, "") == -1) {
      perror ("mount: /proc");
      /* Non-fatal. */
    }
  }
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

/* Display a directory on stderr.  This is used for debugging only. */
static char
dirtype (int dt)
{
  switch (dt) {
  case DT_BLK: return 'b';
  case DT_CHR: return 'c';
  case DT_DIR: return 'd';
  case DT_FIFO: return 'p';
  case DT_LNK: return 'l';
  case DT_REG: return '-';
  case DT_SOCK: return 's';
  case DT_UNKNOWN: return 'u';
  default: return '?';
  }
}

static void
show_directory (const char *dirname)
{
  DIR *dir;
  struct dirent *d;
  struct stat statbuf;
  char link[PATH_MAX+1];
  ssize_t n;

  fprintf (stderr, "febootstrap: debug: listing directory %s\n", dirname);

  if (chdir (dirname) == -1) {
    perror (dirname);
    return;
  }

  dir = opendir (".");
  if (!dir) {
    perror (dirname);
    chdir ("/");
    return;
  }

  while ((d = readdir (dir)) != NULL) {
    fprintf (stderr, "%5d %c %-16s", d->d_ino, dirtype (d->d_type), d->d_name);
    if (lstat (d->d_name, &statbuf) >= 0) {
      fprintf (stderr, " %06o %d %d:%d",
               statbuf.st_mode, statbuf.st_size,
               statbuf.st_uid, statbuf.st_gid);
      if (S_ISLNK (statbuf.st_mode)) {
        n = readlink (d->d_name, link, PATH_MAX);
        if (n >= 0) {
          link[n] = '\0';
          fprintf (stderr, " -> %s", link);
        }
      }
    }
    fprintf (stderr, "\n");
  }

  closedir (dir);
  chdir ("/");
}
