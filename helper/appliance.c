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
#include <limits.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <fnmatch.h>
#include <sys/stat.h>
#include <assert.h>

#include "error.h"
#include "fts_.h"
#include "full-write.h"
#include "xalloc.h"
#include "xvasprintf.h"

#include "helper.h"

/* Buffer size used in copy operations throughout.  Large for
 * greatest efficiency.
 */
#define BUFFER_SIZE 65536

static void iterate_inputs (char **inputs, int nr_inputs);
static void iterate_input_directory (const char *dirname, int dirfd);
static void write_kernel_modules (const char *whitelist, const char *modpath);
static void write_hostfiles (const char *hostfiles_file);
static void write_to_fd (const void *buffer, size_t len);
static void write_file_to_fd (const char *filename);
static void write_file_len_to_fd (const char *filename, size_t len);
static void write_padding (size_t len);
static void cpio_append_fts_entry (FTSENT *entry);
static void cpio_append_stat (const char *filename, struct stat *);
static void cpio_append (const char *filename);
static void cpio_append_trailer (void);

static int out_fd = -1;
static off_t out_offset = 0;

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
create_appliance (char **inputs, int nr_inputs,
                  const char *whitelist,
                  const char *modpath,
                  const char *initrd)
{
  out_fd = open (initrd, O_WRONLY | O_CREAT | O_TRUNC | O_NOCTTY, 0644);
  if (out_fd == -1)
    error (EXIT_FAILURE, errno, "open: %s", initrd);
  out_offset = 0;

  iterate_inputs (inputs, nr_inputs);

  /* Kernel modules (3). */
  write_kernel_modules (whitelist, modpath);

  cpio_append_trailer ();

  /* Finish off and close output file. */
  if (close (out_fd) == -1)
    error (EXIT_FAILURE, errno, "close: %s", initrd);
}

/* Iterate over the inputs to find out what they are, visiting
 * directories if specified.
 */
static void
iterate_inputs (char **inputs, int nr_inputs)
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
      iterate_input_directory (inputs[i], fd);
    else if (S_ISREG (statbuf.st_mode)) {
      /* Is it a cpio file? */
      char buf[6];
      if (read (fd, buf, 6) == 6 && memcmp (buf, "070701", 6) == 0)
        /* Yes, a cpio file.  This is a skeleton appliance, case (1). */
        write_file_to_fd (inputs[i]);
      else
        /* No, must be hostfiles, case (2). */
        write_hostfiles (inputs[i]);
    }
    else
      error (EXIT_FAILURE, 0, "%s: input is not a regular file or directory",
             inputs[i]);

    close (fd);
  }
}

static void
iterate_input_directory (const char *dirname, int dirfd)
{
  char path[PATH_MAX];
  strcpy (path, dirname);
  size_t len = strlen (dirname);
  path[len++] = '/';

  char *inputs[] = { path };

  DIR *dir = fdopendir (dirfd);
  if (dir == NULL)
    error (EXIT_FAILURE, errno, "fdopendir: %s", dirname);

  struct dirent *d;
  while ((errno = 0, d = readdir (dir)) != NULL) {
    if (d->d_name[0] == '.') /* ignore ., .. and any hidden files. */
      continue;

    strcpy (&path[len], d->d_name);
    iterate_inputs (inputs, 1);
  }

  if (errno != 0)
    error (EXIT_FAILURE, errno, "readdir: %s", dirname);

  if (closedir (dir) == -1)
    error (EXIT_FAILURE, errno, "closedir: %s", dirname);
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
write_kernel_modules (const char *whitelist_file, const char *modpath)
{
  char **whitelist = NULL;
  if (whitelist_file != NULL)
    whitelist = load_file (whitelist_file);

  char *paths[2] = { (char *) modpath, NULL };
  FTS *fts = fts_open (paths, FTS_COMFOLLOW|FTS_PHYSICAL, NULL);
  if (fts == NULL)
    error (EXIT_FAILURE, errno, "write_kernel_modules: fts_open: %s", modpath);

  for (;;) {
    errno = 0;
    FTSENT *entry = fts_read (fts);
    if (entry == NULL && errno != 0)
      error (EXIT_FAILURE, errno, "write_kernel_modules: fts_read: %s", modpath);
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
            cpio_append_fts_entry (entry);
            break;
          } else if (r != FNM_NOMATCH)
            error (EXIT_FAILURE, 0, "internal error: fnmatch ('%s', '%s', %d) returned unexpected non-zero value %d\n",
                   whitelist[j], entry->fts_name, 0, r);
        } /* for (j) */
      } else { /* whitelist == NULL, always include */
        if (verbose >= 2)
          fprintf (stderr, "including kernel module %s\n", entry->fts_name);
        cpio_append_fts_entry (entry);
      }
    } else
      /* It's some other sort of file, or a directory, always include. */
      cpio_append_fts_entry (entry);
  }

  if (fts_close (fts) == -1)
    error (EXIT_FAILURE, errno, "write_kernel_modules: fts_close: %s", modpath);
}

/* Copy the host files.
 *
 * Read the list of entries in hostfiles (which may contain
 * wildcards).  Look them up in the filesystem, and add those files
 * that exist.  Ignore any files that don't exist or are not readable.
 */
static void
write_hostfiles (const char *hostfiles_file)
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

        cpio_append (tmp);

        free (tmp);
      }
    }
    /* Else does this file/directory/whatever exist? */
    else if (lstat (hostfile, &statbuf) == 0) {
      if (verbose >= 2)
        fprintf (stderr, "including host file %s (directly referenced)\n",
                 hostfile);

      cpio_append_stat (hostfile, &statbuf);
    } /* Ignore files that don't exist. */
  }
}

/* Copy contents of buffer to out_fd and keep out_offset correct. */
static void
write_to_fd (const void *buffer, size_t len)
{
  if (full_write (out_fd, buffer, len) != len)
    error (EXIT_FAILURE, errno, "write");
  out_offset += len;
}

/* Copy contents of file to out_fd. */
static void
write_file_to_fd (const char *filename)
{
  char buffer[BUFFER_SIZE];
  int fd2;
  ssize_t r;

  if (verbose >= 2)
    fprintf (stderr, "write_file_to_fd %s -> %d\n", filename, out_fd);

  fd2 = open (filename, O_RDONLY);
  if (fd2 == -1)
    error (EXIT_FAILURE, errno, "open: %s", filename);
  for (;;) {
    r = read (fd2, buffer, sizeof buffer);
    if (r == 0)
      break;
    if (r == -1) {
      if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
        continue;
      error (EXIT_FAILURE, errno, "read: %s", filename);
    }
    write_to_fd (buffer, r);
  }

  if (close (fd2) == -1)
    error (EXIT_FAILURE, errno, "close: %s", filename);
}

/* Copy file of given length to output, and fail if the file has
 * changed size.
 */
static void
write_file_len_to_fd (const char *filename, size_t len)
{
  char buffer[BUFFER_SIZE];
  size_t count = 0;

  if (verbose >= 2)
    fprintf (stderr, "write_file_to_fd %s -> %d\n", filename, out_fd);

  int fd2 = open (filename, O_RDONLY);
  if (fd2 == -1)
    error (EXIT_FAILURE, errno, "open: %s", filename);
  for (;;) {
    ssize_t r = read (fd2, buffer, sizeof buffer);
    if (r == 0)
      break;
    if (r == -1) {
      if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
        continue;
      error (EXIT_FAILURE, errno, "read: %s", filename);
    }
    write_to_fd (buffer, r);
    count += r;
    if (count > len)
      error (EXIT_FAILURE, 0, "write_file_len_to_fd: %s: file has increased in size\n", filename);
  }

  if (close (fd2) == -1)
    error (EXIT_FAILURE, errno, "close: %s", filename);

  if (count != len)
    error (EXIT_FAILURE, 0, "febootstrap-supermin-helper: write_file_len_to_fd: %s: file has changed size\n", filename);
}

/* Append the file pointed to by FTSENT to the cpio output. */
static void
cpio_append_fts_entry (FTSENT *entry)
{
  if (entry->fts_info & FTS_NS || entry->fts_info & FTS_NSOK)
    cpio_append (entry->fts_path);
  else
    cpio_append_stat (entry->fts_path, entry->fts_statp);
}

/* Append the file named 'filename' to the cpio output. */
static void
cpio_append (const char *filename)
{
  struct stat statbuf;

  if (lstat (filename, &statbuf) == -1)
    error (EXIT_FAILURE, errno, "lstat: %s", filename);
  cpio_append_stat (filename, &statbuf);
}

/* Append the file to the cpio output. */
#define PADDING(len) ((((len) + 3) & ~3) - (len))

#define CPIO_HEADER_LEN (6 + 13*8)

static void
cpio_append_stat (const char *filename, struct stat *statbuf)
{
  const char *orig_filename = filename;

  if (*filename == '/')
    filename++;
  if (*filename == '\0')
    filename = ".";

  if (verbose >= 2)
    fprintf (stderr, "cpio_append_stat %s 0%o -> %d\n",
             orig_filename, statbuf->st_mode, out_fd);

  /* Regular files and symlinks are the only ones that have a "body"
   * in this cpio entry.
   */
  int has_body = S_ISREG (statbuf->st_mode) || S_ISLNK (statbuf->st_mode);

  size_t len = strlen (filename) + 1;

  char header[CPIO_HEADER_LEN + 1];
  snprintf (header, sizeof header,
            "070701"            /* magic */
            "%08X"              /* inode */
            "%08X"              /* mode */
            "%08X" "%08X"       /* uid, gid */
            "%08X"              /* nlink */
            "%08X"              /* mtime */
            "%08X"              /* file length */
            "%08X" "%08X"       /* device holding file major, minor */
            "%08X" "%08X"       /* for specials, device major, minor */
            "%08X"              /* name length (including \0 byte) */
            "%08X",             /* checksum (not used by the kernel) */
            (unsigned) statbuf->st_ino, statbuf->st_mode,
            statbuf->st_uid, statbuf->st_gid,
            (unsigned) statbuf->st_nlink, (unsigned) statbuf->st_mtime,
            has_body ? (unsigned) statbuf->st_size : 0,
            major (statbuf->st_dev), minor (statbuf->st_dev),
            major (statbuf->st_rdev), minor (statbuf->st_rdev),
            (unsigned) len, 0);

  /* Write the header. */
  write_to_fd (header, CPIO_HEADER_LEN);

  /* Follow with the filename, and pad it. */
  write_to_fd (filename, len);
  size_t padding_len = PADDING (CPIO_HEADER_LEN + len);
  write_padding (padding_len);

  /* Follow with the file or symlink content, and pad it. */
  if (has_body) {
    if (S_ISREG (statbuf->st_mode))
      write_file_len_to_fd (orig_filename, statbuf->st_size);
    else if (S_ISLNK (statbuf->st_mode)) {
      char tmp[PATH_MAX];
      if (readlink (orig_filename, tmp, sizeof tmp) == -1)
        error (EXIT_FAILURE, errno, "readlink: %s", orig_filename);
      write_to_fd (tmp, statbuf->st_size);
    }

    padding_len = PADDING (statbuf->st_size);
    write_padding (padding_len);
  }
}

/* CPIO voodoo. */
static void
cpio_append_trailer (void)
{
  struct stat statbuf;
  memset (&statbuf, 0, sizeof statbuf);
  statbuf.st_nlink = 1;
  cpio_append_stat ("TRAILER!!!", &statbuf);

  /* CPIO seems to pad up to the next block boundary, ie. up to
   * the next 512 bytes.
   */
  write_padding (((out_offset + 511) & ~511) - out_offset);
  assert ((out_offset & 511) == 0);
}

/* Write 'len' bytes of zeroes out. */
static void
write_padding (size_t len)
{
  static const char buffer[512] = { 0 };

  while (len > 0) {
    size_t n = len < sizeof buffer ? len : sizeof buffer;
    write_to_fd (buffer, n);
    len -= n;
  }
}
