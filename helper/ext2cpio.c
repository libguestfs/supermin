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
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <sys/stat.h>
#include <assert.h>

#include "error.h"

#include "helper.h"
#include "ext2internal.h"

/* This function must unpack the cpio file and add the files it
 * contains to the ext2 filesystem.  Essentially this is doing the
 * same thing as the kernel init/initramfs.c code.  Note that we
 * assume that the cpio is uncompressed newc format and can't/won't
 * deal with anything else.  All this cpio parsing code is copied to
 * some extent from init/initramfs.c in the kernel.
 */
#define N_ALIGN(len) ((((len) + 1) & ~3) + 2)

static unsigned long cpio_ino, nlink;
static mode_t mode;
static unsigned long body_len, name_len;
static uid_t uid;
static gid_t gid;
static time_t mtime;
static int dev_major, dev_minor, rdev_major, rdev_minor;
static loff_t curr, next_header;
static FILE *fp;

static void parse_header (char *s);
static int parse_next_entry (void);
static void skip_to_next_header (void);
static void read_file (void);
static char *read_whole_body (void);
static ext2_ino_t maybe_link (void);
static void add_link (ext2_ino_t real_ino);
static void clear_links (void);

void
ext2_cpio_file (const char *cpio_file)
{
  fp = fopen (cpio_file, "r");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "open: %s", cpio_file);

  curr = 0;
  while (parse_next_entry ())
    ;

  fclose (fp);
}

static int
parse_next_entry (void)
{
  clearerr (fp);

  char header[110];

  /* Skip padding and synchronize with the next header. */
 again:
  if (fread (&header[0], 4, 1, fp) != 1) {
    if (feof (fp))
      return 0;
    error (EXIT_FAILURE, errno, "read failure reading cpio file");
  }
  curr += 4;
  if (memcmp (header, "\0\0\0\0", 4) == 0)
    goto again;

  /* Read the rest of the header field. */
  if (fread (&header[4], sizeof header - 4, 1, fp) != 1)
    error (EXIT_FAILURE, errno, "read failure reading cpio file");
  curr += sizeof header - 4;

  if (verbose >= 2)
    fprintf (stderr, "cpio header %s\n", header);

  if (memcmp (header, "070707", 6) == 0)
    error (EXIT_FAILURE, 0, "incorrect cpio method: use -H newc option");
  if (memcmp (header, "070701", 6) != 0)
    error (EXIT_FAILURE, 0, "input is not a cpio file");

  parse_header (header);

  next_header = curr + N_ALIGN(name_len) + body_len;
  next_header = (next_header + 3) & ~3;
  if (name_len <= 0 || name_len > PATH_MAX)
    skip_to_next_header ();
  else if (S_ISLNK (mode)) {
    if (body_len <= 0 || body_len > PATH_MAX)
      skip_to_next_header ();
    else
      read_file ();
  }
  else if (!S_ISREG (mode) && body_len > 0)
    skip_to_next_header (); /* only regular files have bodies */
  else
    read_file (); /* could be file, directory, block special, ... */

  return 1;
}

static void
parse_header (char *s)
{
  unsigned long parsed[12];
  char buf[9];
  int i;

  buf[8] = '\0';
  for (i = 0, s += 6; i < 12; i++, s += 8) {
    memcpy (buf, s, 8);
    parsed[i] = strtoul (buf, NULL, 16);
  }
  cpio_ino = parsed[0]; /* fake inode number from cpio file */
  mode = parsed[1];
  uid = parsed[2];
  gid = parsed[3];
  nlink = parsed[4];
  mtime = parsed[5];
  body_len = parsed[6];
  dev_major = parsed[7];
  dev_minor = parsed[8];
  rdev_major = parsed[9];
  rdev_minor = parsed[10];
  name_len = parsed[11];
}

static void
skip_to_next_header (void)
{
  char buf[65536];

  while (curr < next_header) {
    size_t bytes = (size_t) (next_header - curr);
    if (bytes > sizeof buf)
      bytes = sizeof buf;
    size_t r = fread (buf, 1, bytes, fp);
    if (r == 0)
      error (EXIT_FAILURE, errno, "error or unexpected end of cpio file");
    curr += r;
  }
}

/* Read any sort of file.  The body will only be present for
 * regular files and symlinks.
 */
static void
read_file (void)
{
  errcode_t err;
  int dir_ft;
  char name[N_ALIGN(name_len)+1]; /* asserted above this is <= PATH_MAX */

  if (fread (name, N_ALIGN(name_len), 1, fp) != 1)
    error (EXIT_FAILURE, errno, "read failure reading name field in cpio file");
  curr += N_ALIGN(name_len);

  name[name_len] = '\0';

  if (verbose >= 2)
    fprintf (stderr, "ext2 read_file %s %o\n", name, mode);

  if (strcmp (name, "TRAILER!!!") == 0) {
    clear_links ();
    goto skip;
  }

  /* The name will be something like "bin/ls" or "./bin/ls".  It won't
   * (ever?) be an absolute path.  Skip leading parts, and if it refers
   * to the root directory just skip it entirely.
   */
  char *dirname = name, *basename;
  if (*dirname == '.')
    dirname++;
  if (*dirname == '/')
    dirname++;
  if (*dirname == '\0')
    goto skip;

  ext2_ino_t dir_ino;
  basename = strrchr (dirname, '/');
  if (basename == NULL) {
    basename = dirname;
    dir_ino = EXT2_ROOT_INO;
  } else {
    *basename++ = '\0';

    /* Look up the parent directory. */
    err = ext2fs_namei (fs, EXT2_ROOT_INO, EXT2_ROOT_INO, dirname, &dir_ino);
    if (err != 0)
      error (EXIT_FAILURE, 0, "ext2: parent directory not found: %s: %s",
             dirname, error_message (err));
  }

  if (verbose >= 2)
    fprintf (stderr, "ext2 read_file dirname %s basename %s\n",
             dirname, basename);

  ext2_clean_path (dir_ino, dirname, basename, S_ISDIR (mode));

  /* Create a regular file. */
  if (S_ISREG (mode)) {
    ext2_ino_t ml = maybe_link ();
    ext2_ino_t ino;
    if (ml <= 1) {
      ext2_empty_inode (dir_ino, dirname, basename,
                        mode, uid, gid, mtime, mtime, mtime,
                        0, 0, EXT2_FT_REG_FILE, &ino);
      if (ml == 1)
        add_link (ino);
    }
    else /* ml >= 2 */ {
      /* It's a hard link back to a previous file. */
      ino = ml;
      ext2_link (dir_ino, basename, ino, EXT2_FT_REG_FILE);
    }

    if (body_len) {
      char *buf = read_whole_body ();
      ext2_write_file (ino, buf, body_len, name);
      free (buf);
    }
  }
  /* Create a symlink. */
  else if (S_ISLNK (mode)) {
    ext2_ino_t ino;
    ext2_empty_inode (dir_ino, dirname, basename,
                      mode, uid, gid, mtime, mtime, mtime,
                      0, 0, EXT2_FT_SYMLINK, &ino);

    char *buf = read_whole_body ();
    ext2_write_file (ino, buf, body_len, name);
    free (buf);
  }
  /* Create a directory. */
  else if (S_ISDIR (mode)) {
    ext2_mkdir (dir_ino, dirname, basename,
                mode, uid, gid, mtime, mtime, mtime);
  }
  /* Create a special file. */
  else if (S_ISBLK (mode)) {
    dir_ft = EXT2_FT_BLKDEV;
    goto make_special;
  }
  else if (S_ISCHR (mode)) {
    dir_ft = EXT2_FT_CHRDEV;
    goto make_special;
  } else if (S_ISFIFO (mode)) {
    dir_ft = EXT2_FT_FIFO;
    goto make_special;
  } else if (S_ISSOCK (mode)) {
    dir_ft = EXT2_FT_SOCK;
  make_special:
    /* Just like the kernel, we ignore special files with nlink > 1. */
    if (maybe_link () == 0)
      ext2_empty_inode (dir_ino, dirname, basename,
                        mode, uid, gid, mtime, mtime, mtime,
                        rdev_major, rdev_minor, dir_ft, NULL);
  }

 skip:
  skip_to_next_header ();
}

static char *
read_whole_body (void)
{
  char *buf = malloc (body_len);
  if (buf == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  size_t r = fread (buf, body_len, 1, fp);
  if (r != 1)
    error (EXIT_FAILURE, errno, "read failure reading body in cpio file");
  curr += body_len;

  return buf;
}

struct links {
  struct links *next;
  unsigned long cpio_ino;       /* fake ino from cpio file */
  int minor;
  int major;
  ext2_ino_t real_ino;          /* real inode number on ext2 filesystem */
};
static struct links *links_head = NULL;

/* If it's a hard link, return the linked inode number in the real
 * ext2 filesystem.
 *
 * Returns: 0 = not a hard link
 *          1 = possible unresolved hard link
 *          inode number = resolved hard link to this inode
 */
static ext2_ino_t
maybe_link (void)
{
  if (nlink >= 2) {
    struct links *p;
    for (p = links_head; p; p = p->next) {
      if (p->cpio_ino != cpio_ino)
        continue;
      if (p->minor != dev_minor)
        continue;
      if (p->major != dev_major)
        continue;
      return p->real_ino;
    }
    return 1;
  }

  return 0;
}

static void
add_link (ext2_ino_t real_ino)
{
  struct links *p = malloc (sizeof (*p));
  p->cpio_ino = cpio_ino;
  p->minor = dev_minor;
  p->major = dev_major;
  p->real_ino = real_ino;
}

static void
clear_links (void)
{
  /* Don't bother to free the linked list in this short-lived program. */
  links_head = NULL;
}
