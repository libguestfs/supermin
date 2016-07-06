/* supermin 5
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <limits.h>
#include <errno.h>
#include <assert.h>
#include <inttypes.h>

/* Inlining is broken in the ext2fs header file.  Disable it by
 * defining the following:
 */
#define NO_INLINE_FUNCS
#include <ext2fs.h>

/* Defining CAML_NAME_SPACE prevents <caml/compatibility.h> from
 * defining some macros that conflict with ext2fs macros.
 */
#define CAML_NAME_SPACE
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

/* fts.h in glibc is broken, forcing us to use the GNUlib alternative. */
#include "fts_.h"

/* How many blocks of size S are needed for storing N bytes. */
#define ROUND_UP(N, S) (((N) + (S) - 1) / (S))

struct ext2_data
{
  ext2_filsys fs;
  int debug;
};

static void initialize (void) __attribute__((constructor));

static void
initialize (void)
{
  initialize_ext2_error_table ();
}

static void ext2_error_to_exception (const char *fn, errcode_t err, const char *filename) __attribute__((noreturn));

static void
ext2_error_to_exception (const char *fn, errcode_t err, const char *filename)
{
  fprintf (stderr, "supermin: %s: %s: %s\n",
	   fn, filename ? : "(no filename))", error_message (err));
  caml_failwith (fn);
}

static void ext2_handle_closed (void) __attribute__((noreturn));

static void
ext2_handle_closed (void)
{
  caml_failwith ("ext2fs: function called on a closed handle");
}

#define Ext2fs_val(v) (*((struct ext2_data *)Data_custom_val(v)))
#define Val_none Val_int(0)
#define Some_val(v) Field(v,0)

static void
ext2_finalize (value fsv)
{
  struct ext2_data data = Ext2fs_val (fsv);

  if (data.fs) {
#ifdef HAVE_EXT2FS_CLOSE2
    ext2fs_close2 (data.fs, EXT2_FLAG_FLUSH_NO_SYNC);
#else
    ext2fs_close (data.fs);
#endif
  }
}

static struct custom_operations ext2_custom_operations = {
  (char *) "ext2fs_custom_operations",
  ext2_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

static value
Val_ext2fs (struct ext2_data *data)
{
  CAMLparam0 ();
  CAMLlocal1 (fsv);

  fsv = caml_alloc_custom (&ext2_custom_operations,
                           sizeof (struct ext2_data), 0, 1);
  Ext2fs_val (fsv) = *data;
  CAMLreturn (fsv);
}

value
supermin_ext2fs_open (value filev, value debugv)
{
  CAMLparam1 (filev);
  CAMLlocal1 (fsv);
  int fs_flags = EXT2_FLAG_RW;
  errcode_t err;
  struct ext2_data data;

#ifdef EXT2_FLAG_64BITS
  fs_flags |= EXT2_FLAG_64BITS;
#endif

  err = ext2fs_open (String_val (filev), fs_flags, 0, 0,
                     unix_io_manager, &data.fs);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_open", err, String_val (filev));

  data.debug = debugv == Val_none ? 0 : Int_val (Some_val (debugv));

  fsv = Val_ext2fs (&data);
  CAMLreturn (fsv);
}

value
supermin_ext2fs_close (value fsv)
{
  CAMLparam1 (fsv);

  ext2_finalize (fsv);

  /* So we don't double-free in the finalizer. */
  Ext2fs_val (fsv).fs = NULL;

  CAMLreturn (Val_unit);
}

value
supermin_ext2fs_read_bitmaps (value fsv)
{
  CAMLparam1 (fsv);
  struct ext2_data data;
  errcode_t err;

  data = Ext2fs_val (fsv);
  if (data.fs == NULL)
    ext2_handle_closed ();

  err = ext2fs_read_bitmaps (data.fs);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_read_bitmaps", err, NULL);

  CAMLreturn (Val_unit);
}

static void ext2_mkdir (ext2_filsys fs, ext2_ino_t dir_ino, const char *dirname, const char *basename, mode_t mode, uid_t uid, gid_t gid, time_t ctime, time_t atime, time_t mtime);
static void ext2_empty_inode (ext2_filsys fs, ext2_ino_t dir_ino, const char *dirname, const char *basename, mode_t mode, uid_t uid, gid_t gid, time_t ctime, time_t atime, time_t mtime, int major, int minor, int dir_ft, ext2_ino_t *ino_ret);
static void ext2_write_file (ext2_filsys fs, ext2_ino_t ino, const char *buf, size_t size, const char *filename);
static void ext2_write_host_file (ext2_filsys fs, ext2_ino_t ino, const char *src, const char *filename);
static void ext2_link (ext2_filsys fs, ext2_ino_t dir_ino, const char *basename, ext2_ino_t ino, int dir_ft);
static void ext2_clean_path (ext2_filsys fs, ext2_ino_t dir_ino, const char *dirname, const char *basename, int isdir);
static void ext2_copy_file (struct ext2_data *data, const char *src, const char *dest);

/* Copy the host filesystem file/directory 'src' to the destination
 * 'dest'.  Directories are NOT copied recursively - the directory is
 * simply created.  See function below for recursive copy.
 */
value
supermin_ext2fs_copy_file_from_host (value fsv, value srcv, value destv)
{
  CAMLparam3 (fsv, srcv, destv);
  const char *src = String_val (srcv);
  const char *dest = String_val (destv);
  struct ext2_data data;

  data = Ext2fs_val (fsv);
  if (data.fs == NULL)
    ext2_handle_closed ();

  ext2_copy_file (&data, src, dest);

  CAMLreturn (Val_unit);
}

/* Copy the host directory 'srcdir' to the destination directory
 * 'destdir'.  The copy is done recursively.
 */
value
supermin_ext2fs_copy_dir_recursively_from_host (value fsv,
                                                value srcdirv, value destdirv)
{
  CAMLparam3 (fsv, srcdirv, destdirv);
  const char *srcdir = String_val (srcdirv);
  const char *destdir = String_val (destdirv);
  size_t srclen = strlen (srcdir);
  struct ext2_data data;
  char *paths[2];
  FTS *fts;
  FTSENT *entry;
  const char *srcpath;
  char *destpath;
  size_t i, n;
  int r;

  data = Ext2fs_val (fsv);
  if (data.fs == NULL)
    ext2_handle_closed ();

  paths[0] = (char *) srcdir;
  paths[1] = NULL;
  fts = fts_open (paths, FTS_COMFOLLOW|FTS_PHYSICAL, NULL);
  if (fts == NULL)
    unix_error (errno, (char *) "fts_open", srcdirv);

  for (;;) {
    errno = 0;
    entry = fts_read (fts);
    if (entry == NULL && errno != 0)
      unix_error (errno, (char *) "fts_read", srcdirv);
    if (entry == NULL)
      break;

    /* Ignore directories being visited in post-order. */
    if (entry->fts_info == FTS_DP)
      continue;

    /* Copy the file. */
    srcpath = entry->fts_path + srclen;
    if (strcmp (destdir, "/") == 0) {
      if (srcpath[0] == '\0')
        r = asprintf (&destpath, "/");
      else
        r = asprintf (&destpath, "/%s", srcpath);
    } else {
      if (srcpath[0] == '\0')
        r = asprintf (&destpath, "%s", destdir);
      else
        r = asprintf (&destpath, "%s/%s", destdir, srcpath);
    }
    if (r == -1)
      caml_raise_out_of_memory ();

    /* Destpath must not have a trailing '/' (except for root dir "/"). */
    n = strlen (destpath);
    if (n >= 2 && destpath[n-1] == '/') destpath[n-1] = '\0';

    /* Remove any double // from within destpath. */
    n = strlen (destpath);
    for (i = 0; i < n-1; ++i) {
      if (destpath[i] == '/' && destpath[i+1] == '/') {
        memmove (&destpath[i], &destpath[i+1], n-(i+1));
        destpath[n-1] = '\0';
        i--;
        n--;
      }
    }

    ext2_copy_file (&data, entry->fts_path, destpath);
    free (destpath);
  }

  if (fts_close (fts) == -1)
    unix_error (errno, (char *) "fts_close", srcdirv);

  CAMLreturn (Val_unit);
}

/* Change the permissions of 'path' to 'mode'.
 */
value
supermin_ext2fs_chmod (value fsv, value pathv, value modev)
{
  CAMLparam3 (fsv, pathv, modev);
  const char *path = String_val (pathv);
  mode_t mode = Int_val (modev);
  errcode_t err;
  struct ext2_data data;

  data = Ext2fs_val (fsv);
  if (data.fs == NULL)
    ext2_handle_closed ();

  ext2_ino_t ino;
  ++path;
  if (*path == 0) {             /* "/" */
    ino = EXT2_ROOT_INO;
  } else {                      /* "/foo" */
    err = ext2fs_namei (data.fs, EXT2_ROOT_INO, EXT2_ROOT_INO, path, &ino);
    if (err != 0)
      ext2_error_to_exception ("ext2fs_namei", err, path);
  }

  struct ext2_inode inode;
  err = ext2fs_read_inode (data.fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_read_inode", err, path);
  inode.i_mode = (inode.i_mode & ~07777) | mode;
  err = ext2fs_write_inode (data.fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_write_inode", err, path);

  CAMLreturn (Val_unit);
}

/* Change the ownership of 'path' to 'uid' and 'gid'.
 */
value
supermin_ext2fs_chown (value fsv, value pathv, value uidv, value gidv)
{
  CAMLparam4 (fsv, pathv, uidv, gidv);
  const char *path = String_val (pathv);
  int uid = Int_val (uidv);
  int gid = Int_val (gidv);
  errcode_t err;
  struct ext2_data data;

  data = Ext2fs_val (fsv);
  if (data.fs == NULL)
    ext2_handle_closed ();

  ext2_ino_t ino;
  ++path;
  if (*path == 0) {             /* "/" */
    ino = EXT2_ROOT_INO;
  } else {                      /* "/foo" */
    err = ext2fs_namei (data.fs, EXT2_ROOT_INO, EXT2_ROOT_INO, path, &ino);
    if (err != 0)
      ext2_error_to_exception ("ext2fs_namei", err, path);
  }

  struct ext2_inode inode;
  err = ext2fs_read_inode (data.fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_read_inode", err, path);
  inode.i_uid = uid;
  inode.i_gid = gid;
  err = ext2fs_write_inode (data.fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_write_inode", err, path);

  CAMLreturn (Val_unit);
}

static void
ext2_mkdir (ext2_filsys fs,
            ext2_ino_t dir_ino, const char *dirname, const char *basename,
            mode_t mode, uid_t uid, gid_t gid,
            time_t ctime, time_t atime, time_t mtime)
{
  errcode_t err;

  mode = LINUX_S_IFDIR | (mode & 03777);

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
    ext2_error_to_exception ("ext2fs_new_inode", err, basename);

 try_again:
  err = ext2fs_mkdir (fs, dir_ino, ino, basename);
  if (err != 0) {
    /* See: http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=217892 */
    if (err == EXT2_ET_DIR_NO_SPACE) {
      err = ext2fs_expand_dir (fs, dir_ino);
      if (err)
        ext2_error_to_exception ("ext2fs_expand_dir", err, dirname);
      goto try_again;
    } else
      ext2_error_to_exception ("ext2fs_mkdir", err, basename);
  }

  /* Copy the final permissions, UID etc. to the inode. */
  struct ext2_inode inode;
  err = ext2fs_read_inode (fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_read_inode", err, basename);
  inode.i_mode = mode;
  inode.i_uid = uid;
  inode.i_gid = gid;
  inode.i_ctime = ctime;
  inode.i_atime = atime;
  inode.i_mtime = mtime;
  err = ext2fs_write_inode (fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_write_inode", err, basename);
}

static void
ext2_empty_inode (ext2_filsys fs,
                  ext2_ino_t dir_ino, const char *dirname, const char *basename,
                  mode_t mode, uid_t uid, gid_t gid,
                  time_t ctime, time_t atime, time_t mtime,
                  int major, int minor, int dir_ft, ext2_ino_t *ino_ret)
{
  errcode_t err;
  struct ext2_inode inode;
  ext2_ino_t ino;

  err = ext2fs_new_inode (fs, dir_ino, mode, 0, &ino);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_new_inode", err, dirname);

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
    ext2_error_to_exception ("ext2fs_write_inode", err, dirname);

  ext2_link (fs, dir_ino, basename, ino, dir_ft);

  ext2fs_inode_alloc_stats2 (fs, ino, 1, 0);

  if (ino_ret)
    *ino_ret = ino;
}

/* You must create the file first with ext2_empty_inode. */
static void
ext2_write_file (ext2_filsys fs,
                 ext2_ino_t ino, const char *buf, size_t size,
                 const char *filename)
{
  errcode_t err;
  ext2_file_t file;
  err = ext2fs_file_open2 (fs, ino, NULL, EXT2_FILE_WRITE, &file);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_file_open2", err, filename);

  /* ext2fs_file_write cannot deal with partial writes.  You have
   * to write the entire file in a single call.
   */
  unsigned int written;
  err = ext2fs_file_write (file, buf, size, &written);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_file_write", err, filename);
  if ((size_t) written != size)
    caml_failwith ("ext2fs_file_write: file size != bytes written");

  err = ext2fs_file_flush (file);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_file_flush", err, filename);
  err = ext2fs_file_close (file);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_file_close", err, filename);

  /* Update the true size in the inode. */
  struct ext2_inode inode;
  err = ext2fs_read_inode (fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_read_inode", err, filename);
  inode.i_size = size;
  err = ext2fs_write_inode (fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_write_inode", err, filename);
}

/* Same as ext2_write_file, but it copies the file contents from the
 * host.  You must create the file first with ext2_empty_inode, and
 * the host file must be a regular file.
 */
static void
ext2_write_host_file (ext2_filsys fs,
                      ext2_ino_t ino,
                      const char *src, /* source (host) file */
                      const char *filename)
{
  int fd;
  char buf[BUFSIZ];
  ssize_t r;
  size_t size = 0;
  errcode_t err;
  ext2_file_t file;
  unsigned int written;

  fd = open (src, O_RDONLY);
  if (fd == -1) {
    static int warned = 0;

    /* We skip unreadable files.  However if the error is -EACCES then
     * modify the message so as not to frighten the horses.
     */
    fprintf (stderr, "supermin: warning: %s: %m (ignored)\n", filename);
    if (errno == EACCES && !warned) {
      fprintf (stderr,
               "Some distro files are not public readable, so supermin cannot copy them\n"
               "into the appliance.  This is a problem with your Linux distro.  Please ask\n"
               "your distro to stop doing pointless security by obscurity.\n"
               "You can ignore these warnings.  You *do not* need to use sudo.\n");
      warned = 1;
    }
    return;
  }

  err = ext2fs_file_open2 (fs, ino, NULL, EXT2_FILE_WRITE, &file);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_file_open2", err, filename);

  while ((r = read (fd, buf, sizeof buf)) > 0) {
    err = ext2fs_file_write (file, buf, r, &written);
    if (err != 0)
      ext2_error_to_exception ("ext2fs_file_open2", err, filename);
    if ((ssize_t) written != r)
      caml_failwith ("ext2fs_file_write: requested write size != bytes written");
    size += written;
  }

  if (r == -1)
    unix_error (errno, (char *) "read", caml_copy_string (filename));

  if (close (fd) == -1)
    unix_error (errno, (char *) "close", caml_copy_string (filename));

  /* Flush out the ext2 file. */
  err = ext2fs_file_flush (file);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_file_flush", err, filename);
  err = ext2fs_file_close (file);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_file_close", err, filename);

  /* Update the true size in the inode. */
  struct ext2_inode inode;
  err = ext2fs_read_inode (fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_read_inode", err, filename);
  inode.i_size = size;
  err = ext2fs_write_inode (fs, ino, &inode);
  if (err != 0)
    ext2_error_to_exception ("ext2fs_write_inode", err, filename);
}

/* This is just a wrapper around ext2fs_link which calls
 * ext2fs_expand_dir as necessary if the directory fills up.  See
 * definition of expand_dir in the sources of debugfs.
 */
static void
ext2_link (ext2_filsys fs,
           ext2_ino_t dir_ino, const char *basename, ext2_ino_t ino, int dir_ft)
{
  errcode_t err;

 again:
  err = ext2fs_link (fs, dir_ino, basename, ino, dir_ft);

  if (err == EXT2_ET_DIR_NO_SPACE) {
    err = ext2fs_expand_dir (fs, dir_ino);
    if (err != 0)
      ext2_error_to_exception ("ext2fs_expand_dir", err, basename);
    goto again;
  }

  if (err != 0)
    ext2_error_to_exception ("ext2fs_link", err, basename);
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
static void
ext2_clean_path (ext2_filsys fs, ext2_ino_t dir_ino,
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
      ext2_error_to_exception ("ext2fs_read_inode", err, basename);
    inode.i_links_count--;
    err = ext2fs_write_inode (fs, ino, &inode);
    if (err != 0)
      ext2_error_to_exception ("ext2fs_write_inode", err, basename);

    err = ext2fs_unlink (fs, dir_ino, basename, 0, 0);
    if (err != 0)
      ext2_error_to_exception ("ext2fs_unlink_inode", err, basename);

    if (inode.i_links_count == 0) {
      inode.i_dtime = time (NULL);
      err = ext2fs_write_inode (fs, ino, &inode);
      if (err != 0)
        ext2_error_to_exception ("ext2fs_write_inode", err, basename);

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

/* Copy a file (or directory etc) from the host. */
static void
ext2_copy_file (struct ext2_data *data, const char *src, const char *dest)
{
  errcode_t err;
  struct stat statbuf;
  struct statvfs statvfsbuf;
  size_t blocks;

  if (data->debug >= 3)
    printf ("supermin: ext2: copy_file %s -> %s\n", src, dest);

  if (lstat (src, &statbuf) == -1)
    unix_error (errno, (char *) "lstat", caml_copy_string (src));

  /* Check we're not about to run out of space on the output device.
   * Note we cheat by looking at fs->device_name (which is the output
   * file).  We could store this filename separately.
   */
  if (data->fs->device_name && statvfs (data->fs->device_name, &statvfsbuf) == 0) {
    uint64_t space = statvfsbuf.f_bavail * statvfsbuf.f_bsize;
    uint64_t estimate = 128*1024 + 2 * statbuf.st_size;

    if (space < estimate)
      unix_error (ENOSPC, (char *) "statvfs",
                  caml_copy_string (data->fs->device_name));
  }

  /* Check that we have enough free blocks to store the resulting blocks
   * for this file.  The file might need more than that in the filesystem,
   * but at least this provides a quick check to avoid failing later on.
   */
  blocks = ROUND_UP (statbuf.st_size, data->fs->blocksize);
  if (blocks > ext2fs_free_blocks_count (data->fs->super)) {
    fprintf (stderr, "supermin: %s: needed %zu blocks (%d each) for "
                     "%" PRIu64 " bytes, available only %llu\n",
             src, blocks, data->fs->blocksize, (uint64_t) statbuf.st_size,
             ext2fs_free_blocks_count (data->fs->super));
    unix_error (ENOSPC, (char *) "block size",
                data->fs->device_name ? caml_copy_string (data->fs->device_name) : Val_none);
  }

  /* Sanity check the path.  These rules are always true for the paths
   * passed to us here from the appliance layer.  The assertions just
   * verify that the rules haven't changed.
   */
  size_t n = strlen (dest);
  assert (n <= PATH_MAX);
  assert (n > 0);
  assert (dest[0] == '/'); /* always absolute path */
  assert (n == 1 || dest[n-1] != '/'); /* no trailing slash */

  /* Don't make the root directory, it always exists.  This simplifies
   * the code that follows.
   */
  if (n == 1) return;

  /* XXX There is some confusion between 'src' and 'dest' in the
   * following code, meaning we are likely following the structure of
   * the host filesystem when adding files from the base image.  This
   * is because the code was copied and pasted from supermin 4 where
   * there was no such distinction.
   */
  char *dirname;
  const char *basename;
  const char *p = strrchr (dest, '/');
  ext2_ino_t dir_ino;
  if (dest == p) {     /* "/foo" */
    dirname = strdup ("/");
    basename = dest+1;
    dir_ino = EXT2_ROOT_INO;
  } else {                      /* "/foo/bar" */
    dirname = strndup (dest, p-dest);
    basename = p+1;

    /* If the parent directory is a symlink to another directory, then
     * we want to look up the target directory as an absolute path
     * (RHBZ#698089).  We really want GNU coreutils 'readlink -f' so
     * we might as well just run it.
     */
    struct stat stat1, stat2;
    if (lstat (dirname, &stat1) == 0 && S_ISLNK (stat1.st_mode) &&
	stat (dirname, &stat2) == 0 && S_ISDIR (stat2.st_mode)) {
      char cmd[strlen (dirname) + 100];
      FILE *fp;
      char *new_dirname;
      size_t len;

      /* XXX quoting, although this is from a trusted source */
      snprintf (cmd, sizeof cmd, "readlink -f '%s'", dirname);
      fp = popen (cmd, "r");
      if (fp == NULL)
	goto cont;
      new_dirname = malloc (PATH_MAX+1);
      if (new_dirname == NULL) {
	pclose (fp);
	goto cont;
      }
      if (fgets (new_dirname, PATH_MAX, fp) == NULL) {
	pclose (fp);
	free (new_dirname);
	goto cont;
      }
      pclose (fp);

      len = strlen (new_dirname);
      if (len >= 1 &&
	  new_dirname[len-1] == '\n')
	new_dirname[len-1] = '\0';

      free (dirname);
      dirname = new_dirname;
    }
  cont:

    /* Look up the parent directory. */
    err = ext2fs_namei (data->fs, EXT2_ROOT_INO, EXT2_ROOT_INO, dirname, &dir_ino);
    if (err != 0) {
      /* This is the most popular supermin "WTF" error, so make
       * sure we capture as much information as possible.
       */
      fprintf (stderr, "supermin: *** parent directory not found ***\n");
      fprintf (stderr, "supermin: When reporting this error:\n");
      fprintf (stderr, "supermin: please include ALL the debugging information below\n");
      fprintf (stderr, "supermin: AND tell us what system you are running this on.\n");
      fprintf (stderr, "     src=%s\n    dest=%s\n dirname=%s\nbasename=%s\n",
	       src, dest, dirname, basename);
      ext2_error_to_exception ("ext2fs_namei: parent directory not found",
			       err, dirname);
    }
  }

  ext2_clean_path (data->fs, dir_ino, dirname, basename, S_ISDIR (statbuf.st_mode));

  int dir_ft;

  /* Create regular file. */
  if (S_ISREG (statbuf.st_mode)) {
    /* XXX Hard links get duplicated here. */
    ext2_ino_t ino;

    ext2_empty_inode (data->fs, dir_ino, dirname, basename,
                      statbuf.st_mode, statbuf.st_uid, statbuf.st_gid,
                      statbuf.st_ctime, statbuf.st_atime, statbuf.st_mtime,
                      0, 0, EXT2_FT_REG_FILE, &ino);

    if (statbuf.st_size > 0)
      ext2_write_host_file (data->fs, ino, src, dest);
  }
  /* Create a symlink. */
  else if (S_ISLNK (statbuf.st_mode)) {
    ext2_ino_t ino;
    ext2_empty_inode (data->fs, dir_ino, dirname, basename,
                      statbuf.st_mode, statbuf.st_uid, statbuf.st_gid,
                      statbuf.st_ctime, statbuf.st_atime, statbuf.st_mtime,
                      0, 0, EXT2_FT_SYMLINK, &ino);

    char buf[PATH_MAX+1];
    ssize_t r = readlink (src, buf, sizeof buf);
    if (r == -1)
      unix_error (errno, (char *) "readlink", caml_copy_string (src));
    ext2_write_file (data->fs, ino, buf, r, dest);
  }
  /* Create directory. */
  else if (S_ISDIR (statbuf.st_mode))
    ext2_mkdir (data->fs, dir_ino, dirname, basename,
                statbuf.st_mode, statbuf.st_uid, statbuf.st_gid,
                statbuf.st_ctime, statbuf.st_atime, statbuf.st_mtime);
  /* Create a special file. */
  else if (S_ISBLK (statbuf.st_mode)) {
    dir_ft = EXT2_FT_BLKDEV;
    goto make_special;
  }
  else if (S_ISCHR (statbuf.st_mode)) {
    dir_ft = EXT2_FT_CHRDEV;
    goto make_special;
  } else if (S_ISFIFO (statbuf.st_mode)) {
    dir_ft = EXT2_FT_FIFO;
    goto make_special;
  } else if (S_ISSOCK (statbuf.st_mode)) {
    dir_ft = EXT2_FT_SOCK;
  make_special:
    ext2_empty_inode (data->fs, dir_ino, dirname, basename,
                      statbuf.st_mode, statbuf.st_uid, statbuf.st_gid,
                      statbuf.st_ctime, statbuf.st_atime, statbuf.st_mtime,
                      major (statbuf.st_rdev), minor (statbuf.st_rdev),
                      dir_ft, NULL);
  }

  free (dirname);
}
