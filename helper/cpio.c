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
#include <unistd.h>
#include <limits.h>
#include <fcntl.h>
#include <errno.h>
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

static int out_fd = -1;
static off_t out_offset = 0;

static void write_file_to_fd (const char *filename);
static void write_file_len_to_fd (const char *filename, size_t len);
static void write_padding (size_t len);
static void cpio_append_fts_entry (FTSENT *entry);
static void cpio_append_stat (const char *filename, const struct stat *);
static void cpio_append (const char *filename);
static void cpio_append_trailer (void);

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
    error (EXIT_FAILURE, 0, "supermin-helper: write_file_len_to_fd: %s: file has changed size\n", filename);
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
cpio_append_stat (const char *filename, const struct stat *statbuf)
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

static void
cpio_start (const char *hostcpu, const char *appliance,
            const char *modpath, const char *initrd)
{
  out_fd = open (initrd, O_WRONLY | O_CREAT | O_TRUNC | O_NOCTTY, 0644);
  if (out_fd == -1)
    error (EXIT_FAILURE, errno, "open: %s", initrd);
  out_offset = 0;
}

static void
cpio_end (void)
{
  cpio_append_trailer ();

  /* Finish off and close output file. */
  if (close (out_fd) == -1)
    error (EXIT_FAILURE, errno, "close");
}

struct writer cpio_writer = {
  .wr_start = cpio_start,
  .wr_end = cpio_end,
  .wr_file = cpio_append,
  .wr_file_stat = cpio_append_stat,
  .wr_fts_entry = cpio_append_fts_entry,
  .wr_cpio_file = write_file_to_fd,
};
