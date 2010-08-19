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

#ifndef FEBOOTSTRAP_SUPERMIN_HELPER_H
#define FEBOOTSTRAP_SUPERMIN_HELPER_H

/* main.c */
extern struct timeval start_t;
extern int verbose;

/* appliance.c */
extern void create_appliance (char **inputs, int nr_inputs, const char *whitelist, const char *modpath, const char *initrd);

/* kernel.c */
extern const char *create_kernel (const char *hostcpu, const char *kernel);

/* utils.c */
extern void print_timestamped_message (const char *fs, ...);
extern int64_t timeval_diff (const struct timeval *x, const struct timeval *y);
extern int reverse_filevercmp (const void *p1, const void *p2);
extern void add_string (char ***argv, size_t *n_used, size_t *n_alloc, const char *str);
extern size_t count_strings (char *const *argv);
extern char **read_dir (const char *name);
extern char **filter (char **strings, int (*)(const char *));
extern char **filter_fnmatch (char **strings, const char *patt, int flags);
extern char **filter_notmatching_substring (char **strings, const char *sub);
extern void sort (char **strings, int (*compare) (const void *, const void *));
extern int isdir (const char *path);
extern char **load_file (const char *filename);

#endif /* FEBOOTSTRAP_SUPERMIN_HELPER_H */
