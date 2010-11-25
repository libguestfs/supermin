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
#include "fts_.h"
#include "xvasprintf.h"

#include "helper.h"
#include "ext2internal.h"

ext2_filsys fs;

/* The ext2 image that we build always has a fixed size, and we 'hope'
 * that the files fit in (otherwise we'll get an error).  Note that
 * the file is sparsely allocated.
 *
 * The downside of allocating a very large initial disk is that the
 * fixed overhead of ext2 is larger (since ext2 calculates it based on
 * the size of the disk).  For a 1GB disk the overhead is
 * approximately 16MB.
 *
 * In future, make this configurable, or determine it from the input
 * files (XXX).
 */
#define APPLIANCE_SIZE (1024*1024*1024)

static void
ext2_start (const char *hostcpu, const char *appliance,
            const char *modpath, const char *initrd)
{
  initialize_ext2_error_table ();

  /* Make the initrd. */
  ext2_make_initrd (modpath, initrd);

  /* Make the appliance sparse image. */
  int fd = open (appliance, O_WRONLY | O_CREAT | O_TRUNC | O_NOCTTY, 0644);
  if (fd == -1)
    error (EXIT_FAILURE, errno, "open: %s", appliance);

  if (lseek (fd, APPLIANCE_SIZE - 1, SEEK_SET) == -1)
    error (EXIT_FAILURE, errno, "lseek");

  char c = 0;
  if (write (fd, &c, 1) != 1)
    error (EXIT_FAILURE, errno, "write");

  if (close (fd) == -1)
    error (EXIT_FAILURE, errno, "close");

  /* Run mke2fs on the file.
   * XXX Quoting, but this string doesn't come from an untrusted source.
   */
  char *cmd = xasprintf ("%s -t ext2 -F%s '%s'",
                         MKE2FS,
                         verbose >= 2 ? "" : "q",
                         appliance);
  int r = system (cmd);
  if (r == -1 || WEXITSTATUS (r) != 0)
    error (EXIT_FAILURE, 0, "%s: failed", cmd);
  free (cmd);

  if (verbose)
    print_timestamped_message ("finished mke2fs");

  /* Open the filesystem. */
  errcode_t err =
    ext2fs_open (appliance, EXT2_FLAG_RW, 0, 0, unix_io_manager, &fs);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_open: %s", error_message (err));

  /* Bitmaps are not loaded by default, so load them.  ext2fs_close will
   * write out any changes.
   */
  err = ext2fs_read_bitmaps (fs);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_read_bitmaps: %s", error_message (err));
}

static void
ext2_end (void)
{
  /* Write out changes and close. */
  errcode_t err = ext2fs_close (fs);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_close: %s", error_message (err));
}

void
ext2_mkdir (ext2_ino_t dir_ino, const char *dirname, const char *basename,
            mode_t mode, uid_t uid, gid_t gid,
            time_t ctime, time_t atime, time_t mtime)
{
  errcode_t err;

  mode = LINUX_S_IFDIR | (mode & 0777);

  /* Does the directory exist?  This is legitimate: we just skip
   * this case.
   */
  ext2_ino_t ino;
  err = ext2fs_namei (fs, EXT2_ROOT_INO, dir_ino, basename, &ino);
  if (err == 0)
    return; /* skip */

  /* Otherwise, create it. */
  err = ext2fs_new_inode (fs, dir_ino, mode, 0, &ino);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_new_inode: %s", error_message (err));

 try_again:
  err = ext2fs_mkdir (fs, dir_ino, ino, basename);
  if (err != 0) {
    /* See: http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=217892 */
    if (err == EXT2_ET_DIR_NO_SPACE) {
      err = ext2fs_expand_dir (fs, dir_ino);
      if (err)
        error (EXIT_FAILURE, 0, "ext2fs_expand_dir: %s/%s: %s",
               dirname, basename, error_message (err));
      goto try_again;
    } else
      error (EXIT_FAILURE, 0, "ext2fs_mkdir: %s/%s: %s",
             dirname, basename, error_message (err));
  }

  /* Copy the final permissions, UID etc. to the inode. */
  struct ext2_inode inode;
  err = ext2fs_read_inode (fs, ino, &inode);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_read_inode: %s", error_message (err));
  inode.i_mode = mode;
  inode.i_uid = uid;
  inode.i_gid = gid;
  inode.i_ctime = ctime;
  inode.i_atime = atime;
  inode.i_mtime = mtime;
  err = ext2fs_write_inode (fs, ino, &inode);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_write_inode: %s", error_message (err));
}

void
ext2_empty_inode (ext2_ino_t dir_ino, const char *dirname, const char *basename,
                  mode_t mode, uid_t uid, gid_t gid,
                  time_t ctime, time_t atime, time_t mtime,
                  int major, int minor, int dir_ft, ext2_ino_t *ino_ret)
{
  errcode_t err;
  struct ext2_inode inode;
  ext2_ino_t ino;

  err = ext2fs_new_inode (fs, dir_ino, mode, 0, &ino);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_new_inode: %s", error_message (err));

  memset (&inode, 0, sizeof inode);
  inode.i_mode = mode;
  inode.i_uid = uid;
  inode.i_gid = gid;
  inode.i_blocks = 0;
  inode.i_links_count = 1;
  inode.i_ctime = ctime;
  inode.i_atime = atime;
  inode.i_mtime = mtime;
  inode.i_size = 0;
  inode.i_block[0] = (minor & 0xff) | (major << 8) | ((minor & ~0xff) << 12);

  err = ext2fs_write_new_inode (fs, ino, &inode);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_write_inode: %s", error_message (err));

  ext2_link (dir_ino, basename, ino, dir_ft);

  ext2fs_inode_alloc_stats2 (fs, ino, 1, 0);

  if (ino_ret)
    *ino_ret = ino;
}

/* You must create the file first with ext2_empty_inode. */
void
ext2_write_file (ext2_ino_t ino, const char *buf, size_t size)
{
  errcode_t err;
  ext2_file_t file;
  err = ext2fs_file_open2 (fs, ino, NULL, EXT2_FILE_WRITE, &file);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_file_open2: %s", error_message (err));

  /* ext2fs_file_write cannot deal with partial writes.  You have
   * to write the entire file in a single call.
   */
  unsigned int written;
  err = ext2fs_file_write (file, buf, size, &written);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_file_write: %s", error_message (err));
  if ((size_t) written != size)
    error (EXIT_FAILURE, 0,
           "ext2fs_file_write: size = %zu != written = %u\n",
           size, written);

  err = ext2fs_file_flush (file);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_file_flush: %s", error_message (err));
  err = ext2fs_file_close (file);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_file_close: %s", error_message (err));

  /* Update the true size in the inode. */
  struct ext2_inode inode;
  err = ext2fs_read_inode (fs, ino, &inode);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_read_inode: %s", error_message (err));
  inode.i_size = size;
  err = ext2fs_write_inode (fs, ino, &inode);
  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_write_inode: %s", error_message (err));
}

/* This is just a wrapper around ext2fs_link which calls
 * ext2fs_expand_dir as necessary if the directory fills up.  See
 * definition of expand_dir in the sources of debugfs.
 */
void
ext2_link (ext2_ino_t dir_ino, const char *basename, ext2_ino_t ino, int dir_ft)
{
  errcode_t err;

 again:
  err = ext2fs_link (fs, dir_ino, basename, ino, dir_ft);

  if (err == EXT2_ET_DIR_NO_SPACE) {
    err = ext2fs_expand_dir (fs, dir_ino);
    if (err != 0)
      error (EXIT_FAILURE, 0, "ext2_link: ext2fs_expand_dir: %s: %s",
             basename, error_message (err));
    goto again;
  }

  if (err != 0)
    error (EXIT_FAILURE, 0, "ext2fs_link: %s: %s",
             basename, error_message (err));
}

static int
release_block (ext2_filsys fs, blk_t *blocknr,
                int blockcnt, void *private)
{
  blk_t block;

  block = *blocknr;
  ext2fs_block_alloc_stats (fs, block, -1);
  return 0;
}

/* unlink or rmdir path, if it exists. */
void
ext2_clean_path (ext2_ino_t dir_ino,
                 const char *dirname, const char *basename,
                 int isdir)
{
  errcode_t err;

  ext2_ino_t ino;
  err = ext2fs_lookup (fs, dir_ino, basename, strlen (basename),
                       NULL, &ino);
  if (err == EXT2_ET_FILE_NOT_FOUND)
    return;

  if (!isdir) {
    struct ext2_inode inode;
    err = ext2fs_read_inode (fs, ino, &inode);
    if (err != 0)
      error (EXIT_FAILURE, 0, "ext2fs_read_inode: %s", error_message (err));
    inode.i_links_count--;
    err = ext2fs_write_inode (fs, ino, &inode);
    if (err != 0)
      error (EXIT_FAILURE, 0, "ext2fs_write_inode: %s", error_message (err));

    err = ext2fs_unlink (fs, dir_ino, basename, 0, 0);
    if (err != 0)
      error (EXIT_FAILURE, 0, "ext2fs_unlink_inode: %s", error_message (err));

    if (inode.i_links_count == 0) {
      inode.i_dtime = time (NULL);
      err = ext2fs_write_inode (fs, ino, &inode);
      if (err != 0)
        error (EXIT_FAILURE, 0, "ext2fs_write_inode: %s", error_message (err));

      if (ext2fs_inode_has_valid_blocks (&inode)) {
	int flags = 0;
	/* From the docs: "BLOCK_FLAG_READ_ONLY is a promise by the
	 * caller that it will not modify returned block number."
	 * RHEL 5 does not have this flag, so just omit it if it is
	 * not defined.
	 */
#ifdef BLOCK_FLAG_READ_ONLY
	flags |= BLOCK_FLAG_READ_ONLY;
#endif
        ext2fs_block_iterate (fs, ino, flags, NULL,
                              release_block, NULL);
      }

      ext2fs_inode_alloc_stats2 (fs, ino, -1, isdir);
    }
  }
  /* else it's a directory, what to do? XXX */
}

/* Read in the whole file into memory.  Check the size is still 'size'. */
static char *
read_whole_file (const char *filename, size_t size)
{
  char *buf = malloc (size);
  if (buf == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  int fd = open (filename, O_RDONLY);
  if (fd == -1)
    error (EXIT_FAILURE, errno, "open: %s", filename);

  size_t n = 0;
  char *p = buf;

  while (n < size) {
    ssize_t r = read (fd, p, size - n);
    if (r == -1)
      error (EXIT_FAILURE, errno, "read: %s", filename);
    if (r == 0)
      error (EXIT_FAILURE, 0,
             "error: file has changed size unexpectedly: %s", filename);
    n += r;
    p += r;
  }

  if (close (fd) == -1)
    error (EXIT_FAILURE, errno, "close: %s", filename);

  return buf;
}

/* Add a file (or directory etc) from the host. */
static void
ext2_file_stat (const char *orig_filename, const struct stat *statbuf)
{
  errcode_t err;

  if (verbose >= 2)
    fprintf (stderr, "ext2_file_stat %s 0%o\n",
             orig_filename, statbuf->st_mode);

  /* Sanity check the path.  These rules are always true for the paths
   * passed to us here from the appliance layer.  The assertions just
   * verify that the rules haven't changed.
   */
  size_t n = strlen (orig_filename);
  assert (n <= PATH_MAX);
  assert (n > 0);
  assert (orig_filename[0] == '/'); /* always absolute path */
  assert (n == 1 || orig_filename[n-1] != '/'); /* no trailing slash */

  /* Don't make the root directory, it always exists.  This simplifies
   * the code that follows.
   */
  if (n == 1) return;

  const char *dirname, *basename;
  const char *p = strrchr (orig_filename, '/');
  ext2_ino_t dir_ino;
  if (orig_filename == p) {     /* "/foo" */
    dirname = "/";
    basename = orig_filename+1;
    dir_ino = EXT2_ROOT_INO;
  } else {                      /* "/foo/bar" */
    dirname = strndup (orig_filename, p-orig_filename);
    basename = p+1;

    /* Look up the parent directory. */
    err = ext2fs_namei (fs, EXT2_ROOT_INO, EXT2_ROOT_INO, dirname, &dir_ino);
    if (err != 0)
      error (EXIT_FAILURE, 0, "ext2: parent directory not found: %s: %s",
             dirname, error_message (err));
  }

  ext2_clean_path (dir_ino, dirname, basename, S_ISDIR (statbuf->st_mode));

  int dir_ft;

  /* Create regular file. */
  if (S_ISREG (statbuf->st_mode)) {
    /* XXX Hard links get duplicated here. */
    ext2_ino_t ino;
    ext2_empty_inode (dir_ino, dirname, basename,
                      statbuf->st_mode, statbuf->st_uid, statbuf->st_gid,
                      statbuf->st_ctime, statbuf->st_atime, statbuf->st_mtime,
                      0, 0, EXT2_FT_REG_FILE, &ino);

    if (statbuf->st_size > 0) {
      char *buf = read_whole_file (orig_filename, statbuf->st_size);
      ext2_write_file (ino, buf, statbuf->st_size);
      free (buf);
    }
  }
  /* Create a symlink. */
  else if (S_ISLNK (statbuf->st_mode)) {
    ext2_ino_t ino;
    ext2_empty_inode (dir_ino, dirname, basename,
                      statbuf->st_mode, statbuf->st_uid, statbuf->st_gid,
                      statbuf->st_ctime, statbuf->st_atime, statbuf->st_mtime,
                      0, 0, EXT2_FT_SYMLINK, &ino);

    char buf[PATH_MAX+1];
    ssize_t r = readlink (orig_filename, buf, sizeof buf);
    if (r == -1)
      error (EXIT_FAILURE, errno, "readlink: %s", orig_filename);
    ext2_write_file (ino, buf, r);
  }
  /* Create directory. */
  else if (S_ISDIR (statbuf->st_mode))
    ext2_mkdir (dir_ino, dirname, basename,
                statbuf->st_mode, statbuf->st_uid, statbuf->st_gid,
                statbuf->st_ctime, statbuf->st_atime, statbuf->st_mtime);
  /* Create a special file. */
  else if (S_ISBLK (statbuf->st_mode)) {
    dir_ft = EXT2_FT_BLKDEV;
    goto make_special;
  }
  else if (S_ISCHR (statbuf->st_mode)) {
    dir_ft = EXT2_FT_CHRDEV;
    goto make_special;
  } else if (S_ISFIFO (statbuf->st_mode)) {
    dir_ft = EXT2_FT_FIFO;
    goto make_special;
  } else if (S_ISSOCK (statbuf->st_mode)) {
    dir_ft = EXT2_FT_SOCK;
  make_special:
    ext2_empty_inode (dir_ino, dirname, basename,
                      statbuf->st_mode, statbuf->st_uid, statbuf->st_gid,
                      statbuf->st_ctime, statbuf->st_atime, statbuf->st_mtime,
                      major (statbuf->st_rdev), minor (statbuf->st_rdev),
                      dir_ft, NULL);
  }
}

static void
ext2_file (const char *filename)
{
  struct stat statbuf;

  if (lstat (filename, &statbuf) == -1)
    error (EXIT_FAILURE, errno, "lstat: %s", filename);
  ext2_file_stat (filename, &statbuf);
}

/* In theory this could be optimized to avoid a namei lookup, but
 * it probably wouldn't make much difference.
 */
static void
ext2_fts_entry (FTSENT *entry)
{
  if (entry->fts_info & FTS_NS || entry->fts_info & FTS_NSOK)
    ext2_file (entry->fts_path);
  else
    ext2_file_stat (entry->fts_path, entry->fts_statp);
}

struct writer ext2_writer = {
  .wr_start = ext2_start,
  .wr_end = ext2_end,
  .wr_file = ext2_file,
  .wr_file_stat = ext2_file_stat,
  .wr_fts_entry = ext2_fts_entry,
  .wr_cpio_file = ext2_cpio_file,
};
