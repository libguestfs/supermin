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

/* This is a private interface used between the parts of the ext2 plugin. */

#ifndef FEBOOTSTRAP_SUPERMIN_EXT2INTERNAL_H
#define FEBOOTSTRAP_SUPERMIN_EXT2INTERNAL_H

/* Inlining is broken in the ext2fs header file.  Disable it by
 * defining the following:
 */
#define NO_INLINE_FUNCS
#include <ext2fs/ext2fs.h>

/* ext2.c */
extern ext2_filsys fs;

extern void ext2_mkdir (ext2_ino_t dir_ino, const char *dirname, const char *basename, mode_t mode, uid_t uid, gid_t gid, time_t ctime, time_t atime, time_t mtime);
extern void ext2_empty_inode (ext2_ino_t dir_ino, const char *dirname, const char *basename, mode_t mode, uid_t uid, gid_t gid, time_t ctime, time_t atime, time_t mtime, int major, int minor, int dir_ft, ext2_ino_t *ino_ret);
extern void ext2_write_file (ext2_ino_t ino, const char *buf, size_t size, const char *orig_filename);
extern void ext2_link (ext2_ino_t dir_ino, const char *basename, ext2_ino_t ino, int dir_ft);
extern void ext2_clean_path (ext2_ino_t dir_ino, const char *dirname, const char *basename, int isdir);

/* ext2cpio.c */
extern void ext2_cpio_file (const char *cpio_file);

/* ext2initrd.c */
extern void ext2_make_initrd (const char *modpath, const char *initrd);

#endif /* FEBOOTSTRAP_SUPERMIN_EXT2INTERNAL_H */
