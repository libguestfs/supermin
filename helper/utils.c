/* febootstrap-supermin-helper reimplementation in C.
 * Copyright (C) 2009-2010, 2012 Red Hat Inc.
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
#include <stdint.h>
#include <string.h>
#include <dirent.h>
#include <errno.h>
#include <fnmatch.h>
#include <inttypes.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <assert.h>

#include "error.h"
#include "filevercmp.h"
#include "hash.h"
#include "hash-pjw.h"
#include "xalloc.h"

#include "helper.h"

/* Compute Y - X and return the result in milliseconds.
 * Approximately the same as this code:
 * http://www.mpp.mpg.de/~huber/util/timevaldiff.c
 */
int64_t
timeval_diff (const struct timeval *x, const struct timeval *y)
{
  int64_t msec;

  msec = (y->tv_sec - x->tv_sec) * 1000;
  msec += (y->tv_usec - x->tv_usec) / 1000;
  return msec;
}

void
print_timestamped_message (const char *fs, ...)
{
  struct timeval tv;
  gettimeofday (&tv, NULL);

  va_list args;
  char *msg;
  int err;

  va_start (args, fs);
  err = vasprintf (&msg, fs, args);
  va_end (args);

  if (err < 0) return;

  fprintf (stderr, "supermin helper [%05" PRIi64 "ms] %s\n",
           timeval_diff (&start_t, &tv), msg);

  free (msg);
}

int
reverse_filevercmp (const void *p1, const void *p2)
{
  const char *s1 = * (char * const *) p1;
  const char *s2 = * (char * const *) p2;

  /* Note, arguments are reversed to achieve a reverse sort. */
  return filevercmp (s2, s1);
}

void
add_string (char ***argv, size_t *n_used, size_t *n_alloc, const char *str)
{
  char *new_str;

  if (*n_used >= *n_alloc)
    *argv = x2nrealloc (*argv, n_alloc, sizeof (char *));

  if (str)
    new_str = xstrdup (str);
  else
    new_str = NULL;

  (*argv)[*n_used] = new_str;

  (*n_used)++;
}

size_t
count_strings (char *const *argv)
{
  size_t argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    ;
  return argc;
}

struct dir_cache {
  char *path;
  char **files;
};

static size_t
dir_cache_hash (void const *x, size_t table_size)
{
  struct dir_cache const *p = x;
  return hash_pjw (p->path, table_size);
}

static bool
dir_cache_compare (void const *x, void const *y)
{
  struct dir_cache const *p = x;
  struct dir_cache const *q = y;
  return strcmp (p->path, q->path) == 0;
}

/* Read a directory into a list of strings.
 *
 * Previously looked up directories are cached and returned quickly,
 * saving some considerable amount of time compared to reading the
 * directory over again.  However this means you really must not
 * alter the array of strings that are returned.
 *
 * Returns an empty list if the directory cannot be opened.
 */
char **
read_dir (const char *name)
{
  static Hash_table *ht = NULL;

  if (!ht)
    ht = hash_initialize (1024, NULL, dir_cache_hash, dir_cache_compare, NULL);

  struct dir_cache key = { .path = (char *) name };
  struct dir_cache *p = hash_lookup (ht, &key);
  if (p)
    return p->files;

  char **files = NULL;
  size_t n_used = 0, n_alloc = 0;

  DIR *dir = opendir (name);
  if (!dir) {
    /* If it fails to open, that's OK, skip to the end. */
    /*perror (name);*/
    goto done;
  }

  for (;;) {
    errno = 0;
    struct dirent *d = readdir (dir);
    if (d == NULL) {
      if (errno != 0)
        /* But if it fails here, after opening and potentially reading
         * part of the directory, that's a proper failure - inform the
         * user and exit.
         */
        error (EXIT_FAILURE, errno, "%s", name);
      break;
    }

    add_string (&files, &n_used, &n_alloc, d->d_name);
  }

  if (closedir (dir) == -1)
    error (EXIT_FAILURE, errno, "closedir: %s", name);

 done:
  /* NULL-terminate the array. */
  add_string (&files, &n_used, &n_alloc, NULL);

  /* Add it to the hash for next time. */
  p = xmalloc (sizeof *p);
  p->path = (char *) name;
  p->files = files;
  p = hash_insert (ht, p);
  assert (p != NULL);

  return files;
}

/* Filter a list of strings, returning only those where f(s) != 0. */
char **
filter (char **strings, int (*f) (const char *))
{
  char **out = NULL;
  size_t n_used = 0, n_alloc = 0;

  int i;
  for (i = 0; strings[i] != NULL; ++i) {
    if (f (strings[i]) != 0)
      add_string (&out, &n_used, &n_alloc, strings[i]);
  }

  add_string (&out, &n_used, &n_alloc, NULL);
  return out;
}

/* Filter a list of strings and return only those matching the wildcard. */
char **
filter_fnmatch (char **strings, const char *patt, int flags)
{
  char **out = NULL;
  size_t n_used = 0, n_alloc = 0;

  int i, r;
  for (i = 0; strings[i] != NULL; ++i) {
    r = fnmatch (patt, strings[i], flags);
    if (r == 0)
      add_string (&out, &n_used, &n_alloc, strings[i]);
    else if (r != FNM_NOMATCH)
      error (EXIT_FAILURE, 0, "internal error: fnmatch ('%s', '%s', %d) returned unexpected non-zero value %d\n",
             patt, strings[i], flags, r);
  }

  add_string (&out, &n_used, &n_alloc, NULL);
  return out;
}

/* Filter a list of strings and return only those which DON'T contain sub. */
char **
filter_notmatching_substring (char **strings, const char *sub)
{
  char **out = NULL;
  size_t n_used = 0, n_alloc = 0;

  int i;
  for (i = 0; strings[i] != NULL; ++i) {
    if (strstr (strings[i], sub) == NULL)
      add_string (&out, &n_used, &n_alloc, strings[i]);
  }

  add_string (&out, &n_used, &n_alloc, NULL);
  return out;
}

/* Sort a list of strings, in place, with the comparison function supplied. */
void
sort (char **strings, int (*compare) (const void *, const void *))
{
  qsort (strings, count_strings (strings), sizeof (char *), compare);
}

/* Return true iff path exists and is a directory.  This version
 * follows symlinks.
 */
int
isdir (const char *path)
{
  struct stat statbuf;

  if (stat (path, &statbuf) == -1)
    return 0;

  return S_ISDIR (statbuf.st_mode);
}

/* Return true iff path exists and is a regular file.  This version
 * follows symlinks.
 */
int
isfile (const char *path)
{
  struct stat statbuf;

  if (stat (path, &statbuf) == -1)
    return 0;

  return S_ISREG (statbuf.st_mode);
}

/* Load in a file, returning a list of lines. */
char **
load_file (const char *filename)
{
  char **lines = 0;
  size_t n_used = 0, n_alloc = 0;

  FILE *fp;
  fp = fopen (filename, "r");
  if (fp == NULL)
    error (EXIT_FAILURE, errno, "fopen: %s", filename);

  char line[4096];
  while (fgets (line, sizeof line, fp)) {
    size_t len = strlen (line);
    if (len > 0 && line[len-1] == '\n')
      line[len-1] = '\0';
    add_string (&lines, &n_used, &n_alloc, line);
  }
  fclose (fp);

  add_string (&lines, &n_used, &n_alloc, NULL);
  return lines;
}
