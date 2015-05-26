/* supermin-helper reimplementation in C.
 * Copyright (C) 2009-2014 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <time.h>
#include <termios.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <asm/unistd.h>

#ifdef HAVE_ZLIB_STATIC
#include <zlib.h>
#endif

#ifdef HAVE_LZMA_STATIC
#include <lzma.h>
#endif

/* Maximum time to wait for the root device to appear (seconds).
 *
 * On slow machines with lots of disks (Koji running the 255 disk test
 * in libguestfs) this really can take several minutes.
 *
 * Note that the actual wait time is approximately double the number
 * given here because there is a delay which doubles until it reaches
 * this value.
 */
#define MAX_ROOT_WAIT 300

extern long init_module (void *, unsigned long, const char *);

/* translation taken from module-init-tools/insmod.c  */
static const char *moderror(int err)
{
  switch (err) {
  case ENOEXEC:
    return "Invalid module format";
  case ENOENT:
    return "Unknown symbol in module";
  case ESRCH:
    return "Module has wrong symbol version";
  case EINVAL:
    return "Invalid parameters";
  default:
    return strerror(err);
  }
}

/* Leave this enabled for now.  When we get more confident in the boot
 * process we can turn this off or make it configurable.
 */
#define verbose 1

static void mount_proc (void);
static void print_uptime (void);
static void read_cmdline (void);
static void insmod (const char *filename);
static void show_directory (const char *dir);

static char cmdline[1024];
static char line[1024];

int
main ()
{
  mount_proc ();

  print_uptime ();
  fprintf (stderr, "supermin: ext2 mini initrd starting up: "
           PACKAGE_VERSION
#ifdef HAVE_ZLIB_STATIC
           " zlib"
#endif
#ifdef HAVE_LZMA_STATIC
           " xz"
#endif
           "\n");

  read_cmdline ();

  /* Create some fixed directories. */
  mkdir ("/dev", 0755);
  mkdir ("/root", 0755);
  mkdir ("/sys", 0755);

  /* Mount /sys. */
  if (verbose)
    fprintf (stderr, "supermin: mounting /sys\n");
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

  /* Look for the ext2 filesystem device.  It's always the last one
   * that was added.  Modern versions of libguestfs supply the
   * expected name of the root device on the command line
   * ("root=/dev/...").  For virtio-scsi this is required, because we
   * must wait for the device to appear after the module is loaded.
   */
  char *root, *path;
  size_t len;
  root = strstr (cmdline, "root=");
  if (root) {
    root += 5;
    if (strncmp (root, "/dev/", 5) == 0)
      root += 5;
    len = strcspn (root, " ");
    root[len] = '\0';

    asprintf (&path, "/sys/block/%s/dev", root);

    uint64_t delay_ns = 250000;
    int virtio_message = 0;
    while (delay_ns <= MAX_ROOT_WAIT * UINT64_C(1000000000)) {
      fp = fopen (path, "r");
      if (fp != NULL)
        goto found;

      if (delay_ns > 1000000000) {
	fprintf (stderr,
		 "supermin: waiting another %" PRIu64 " ns for %s to appear\n",
		 delay_ns, path);
        if (!virtio_message) {
          fprintf (stderr,
                   "This usually means your kernel doesn't support virtio, or supermin was unable\n"
                   "to load some kernel modules (see module loading messages above).\n");
          virtio_message = 1;
        }
      }

      struct timespec t;
      t.tv_sec = delay_ns / 1000000000;
      t.tv_nsec = delay_ns % 1000000000;
      nanosleep (&t, NULL);
      delay_ns *= 2;
    }
  }
  else {
    path = strdup ("/sys/block/xdx/dev");

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
  }

  fprintf (stderr,
           "supermin: no ext2 root device found\n"
           "Please include FULL verbose output in your bug report.\n");
  exit (EXIT_FAILURE);

 found:
  if (verbose)
    fprintf (stderr, "supermin: picked %s as root device\n", path);

  fgets (line, sizeof line, fp);
  int major = atoi (line);
  char *p = line + strcspn (line, ":") + 1;
  int minor = atoi (p);

  fclose (fp);
  if (umount ("/sys") == -1) {
    perror ("umount: /sys");
    exit (EXIT_FAILURE);
  }

  /* Make current process the controlling process of the tty. */
  setsid ();
#ifdef TIOCSCTTY
  if (ioctl (0, TIOCSCTTY, 1) == -1)
    perror ("ioctl: TIOCSCTTY");
#endif

  if (verbose)
    fprintf (stderr, "supermin: creating /dev/root as block special %d:%d\n",
             major, minor);

  if (mknod ("/dev/root", S_IFBLK|0700, makedev (major, minor)) == -1) {
    perror ("mknod: /dev/root");
    exit (EXIT_FAILURE);
  }

  /* Mount new root and chroot to it. */
  if (verbose)
    fprintf (stderr, "supermin: mounting new root on /root\n");
  if (mount ("/dev/root", "/root", "ext2", MS_NOATIME, "") == -1) {
    perror ("mount: /root");
    exit (EXIT_FAILURE);
  }

  /* Note that pivot_root won't work.  See the note in
   * Documentation/filesystems/ramfs-rootfs-initramfs.txt
   * We could remove the old initramfs files, but let's not bother.
   */
  if (verbose)
    fprintf (stderr, "supermin: chroot\n");

  if (chroot ("/root") == -1) {
    perror ("chroot: /root");
    exit (EXIT_FAILURE);
  }

  chdir ("/");

  /* Run /init from ext2 filesystem. */
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

#if HAVE_LZMA_STATIC
static int
ends_with (const char *str, const char *suffix)
{
  if (!str || !suffix)
    return 0;
  size_t lenstr = strlen (str);
  size_t lensuffix = strlen (suffix);
  if (lensuffix >  lenstr)
    return 0;
  return strncmp (str + lenstr - lensuffix, suffix, lensuffix) == 0;
}
#endif

static void
insmod (const char *filename)
{
  size_t size;

  if (verbose)
    fprintf (stderr, "supermin: internal insmod %s\n", filename);

#ifdef HAVE_ZLIB_STATIC
  int capacity = 64*1024;
  char *buf = (char *) malloc (capacity);
  int tmpsize = 8 * 1024;
  char tmp[tmpsize];
  int num;

  errno = 0;
  size = 0;

  if (!buf) {
    perror("malloc");
    exit (EXIT_FAILURE);
  }

#ifdef HAVE_LZMA_STATIC
  if (ends_with(filename, ".xz")) {
    lzma_stream strm = LZMA_STREAM_INIT;
    lzma_ret ret = lzma_stream_decoder(&strm, UINT64_MAX,
          LZMA_CONCATENATED);
    if (verbose)
      fprintf (stderr, "supermin: running xz\n");
    FILE *fd = fopen (filename, "r");
    if (!fd) {
      perror("popen failed");
      exit (EXIT_FAILURE);
    }
    char tmp_out[tmpsize];
    strm.avail_in = 0;
    strm.next_out = tmp_out;
    strm.avail_out = tmpsize;

    lzma_action action = LZMA_RUN;

    while (1) {
      if (strm.avail_in == 0) {
       strm.next_in = tmp;
       strm.avail_in = fread(tmp, 1, tmpsize, fd);

       if (ferror(fd)) {
         // POSIX says that fread() sets errno if
         // an error occurred. ferror() doesn't
         // touch errno.
         perror("Error reading input file");
         exit (EXIT_FAILURE);
       }
       if (feof(fd)) action = LZMA_FINISH;
      }

      ret = lzma_code(&strm, action);

      // Write and check write error before checking decoder error.
      // This way as much data as possible gets written to output
      // even if decoder detected an error.
      if (strm.avail_out == 0 || ret != LZMA_OK) {
          const size_t num =  tmpsize - strm.avail_out;
          if (num > capacity) {
               buf = (char*) realloc (buf, size*2);
               if (!buf) {
                    perror("realloc");
                    exit (EXIT_FAILURE);
               }
               capacity = size;
          }
          memcpy (buf+size, tmp_out, num);
          capacity -= num;
          size += num;
          strm.next_out = tmp_out;
          strm.avail_out = tmpsize;
      }
      if (ret != LZMA_OK) {
       if (ret == LZMA_STREAM_END) {
           break;
       } else {
        perror("internal error");
        exit(EXIT_FAILURE);
       }
     }
    }
    fclose (fd);
    if (verbose)
      fprintf (stderr, "done with xz %d read\n", size);
  } else {
#endif
  gzFile gzfp = gzopen (filename, "rb");
  if (gzfp == NULL) {
    fprintf (stderr, "insmod: gzopen failed: %s", filename);
    exit (EXIT_FAILURE);
  }
  while ((num = gzread (gzfp, tmp, tmpsize)) > 0) {
    if (num > capacity) {
      buf = (char*) realloc (buf, size*2);
      if (!buf) {
        perror("realloc");
        exit (EXIT_FAILURE);
      }
      capacity = size;
    }
    memcpy (buf+size, tmp, num);
    capacity -= num;
    size += num;
  }
  if (num == -1) {
    perror ("insmod: gzread");
    exit (EXIT_FAILURE);
  }
  gzclose (gzfp);
#ifdef HAVE_LZMA_STATIC
}
#endif

#else
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
  size = st.st_size;
  char buf[size];
  size_t offset = 0;
  do {
    ssize_t rc = read (fd, buf + offset, size - offset);
    if (rc == -1) {
      perror ("insmod: read");
      exit (EXIT_FAILURE);
    }
    offset += rc;
  } while (offset < size);
  close (fd);
#endif

  if (init_module (buf, size, "") != 0) {
    fprintf (stderr, "insmod: init_module: %s: %s\n", filename, moderror (errno));
    /* However ignore the error because this can just happen because
     * of a missing device.
     */
  }

#ifdef HAVE_ZLIB_STATIC
  free (buf);
#endif
}

/* Mount /proc unless it's mounted already. */
static void
mount_proc (void)
{
  if (access ("/proc/uptime", R_OK) == -1) {
    mkdir ("/proc", 0755);

    if (verbose)
      fprintf (stderr, "supermin: mounting /proc\n");

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

  fprintf (stderr, "supermin: uptime: %s", line);
}

/* Read /proc/cmdline into cmdline global (or at least the first 1024
 * bytes of it).
 */
static void
read_cmdline (void)
{
  FILE *fp = fopen ("/proc/cmdline", "r");
  if (fp == NULL) {
    perror ("/proc/cmdline");
    return;
  }

  fgets (cmdline, sizeof cmdline, fp);
  fclose (fp);

  fprintf (stderr, "supermin: cmdline: %s", cmdline);
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

  fprintf (stderr, "supermin: debug: listing directory %s\n", dirname);

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
    fprintf (stderr, "%5lu %c %-16s", d->d_ino, dirtype (d->d_type), d->d_name);
    if (lstat (d->d_name, &statbuf) >= 0) {
      fprintf (stderr, " %06o %ld %d:%d",
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
