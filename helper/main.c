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
#include <errno.h>
#include <unistd.h>
#include <getopt.h>
#include <limits.h>
#include <sys/types.h>
#include <sys/time.h>
#include <assert.h>
#include <grp.h>
#include <pwd.h>

#include "error.h"
#include "xstrtol.h"

#include "helper.h"

struct timeval start_t;
int verbose = 0;
int copy_kernel = 0;

enum { HELP_OPTION = CHAR_MAX + 1 };

static const char *options = "f:g:k:u:vV";
static const struct option long_options[] = {
  { "help", 0, 0, HELP_OPTION },
  { "copy-kernel", 0, 0, 0 },
  { "format", required_argument, 0, 'f' },
  { "group", 0, 0, 'g' },
  { "kmods", required_argument, 0, 'k' },
  { "user", 0, 0, 'u' },
  { "verbose", 0, 0, 'v' },
  { "version", 0, 0, 'V' },
  { 0, 0, 0, 0 }
};

static void
usage (FILE *f, const char *progname)
{
  fprintf (f,
          "%s: build the supermin appliance on the fly\n"
          "\n"
          "Usage:\n"
          "  %s [-options] inputs [...] host_cpu kernel initrd\n"
          "  %s -f ext2 inputs [...] host_cpu kernel initrd appliance\n"
          "  %s -f checksum inputs [...] host_cpu\n"
          "  %s --help\n"
          "  %s --version\n"
          "\n"
          "This script is used by febootstrap to build the supermin appliance\n"
          "(kernel and initrd output files).  You should NOT need to run this\n"
          "program directly except if you are debugging tricky supermin\n"
          "appliance problems.\n"
          "\n"
          "NB: The kernel and initrd parameters are OUTPUT parameters.  If\n"
          "those files exist, they are overwritten by the output.\n"
          "\n"
          "Options:\n"
          "  --help\n"
          "       Display this help text and exit.\n"
          "  -f cpio|ext2|checksum | --format cpio|ext2|checksum\n"
          "       Specify output format (default: cpio).\n"
          "  --copy-kernel\n"
          "       Copy the kernel instead of symlinking to it.\n"
          "  -u user\n"
          "       The user name or uid the appliance will run as. Use of this\n"
          "       option requires root privileges.\n"
          "  -g group\n"
          "       The group name or gid the appliance will run as. Use of\n"
          "       this option requires root privileges.\n"
          "  -k file | --kmods file\n"
          "       Specify kernel module whitelist.\n"
          "  --verbose | -v\n"
          "       Enable verbose messages (give multiple times for more verbosity).\n"
          "  --version | -V\n"
          "       Display version number and exit.\n",
          progname, progname, progname, progname, progname, progname);
}

static uid_t
parseuser (const char *id, const char *progname)
{
  struct passwd *pwd;
  int saved_errno;

  errno = 0;
  pwd = getpwnam (id);

  if (NULL == pwd) {
    saved_errno = errno;

    long val;
    int err = xstrtol (id, NULL, 10, &val, "");
    if (err == LONGINT_OK)
      return (uid_t) val;

    fprintf (stderr, "%s: -u option: %s is not a valid user name or uid",
             progname, id);
    if (saved_errno != 0)
      fprintf (stderr, " (getpwnam error: %s)", strerror (saved_errno));
    fprintf (stderr, "\n");
    exit (EXIT_FAILURE);
  }

  return pwd->pw_uid;
}

static gid_t
parsegroup (const char *id, const char *progname)
{
  struct group *grp;
  int saved_errno;

  errno = 0;
  grp = getgrnam (id);

  if (NULL == grp) {
    saved_errno = errno;

    long val;
    int err = xstrtol (id, NULL, 10, &val, "");
    if (err == LONGINT_OK)
      return (gid_t) val;

    fprintf (stderr, "%s: -g option: %s is not a valid group name or gid",
             progname, id);
    if (saved_errno != 0)
      fprintf (stderr, " (getgrnam error: %s)", strerror (saved_errno));
    fprintf (stderr, "\n");
    exit (EXIT_FAILURE);
  }

  return grp->gr_gid;
}

int
main (int argc, char *argv[])
{
  /* First thing: start the clock. */
  gettimeofday (&start_t, NULL);

  const char *format = "cpio";
  const char *whitelist = NULL;

  uid_t euid = geteuid ();
  gid_t egid = getegid ();

  /* Command line arguments. */
  for (;;) {
    int option_index;
    int c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case HELP_OPTION:
      usage (stdout, argv[0]);
      exit (EXIT_SUCCESS);

    case 0:                     /* options which are long only */
      if (strcmp (long_options[option_index].name, "copy-kernel") == 0) {
        copy_kernel = 1;
      } else {
        fprintf (stderr, "%s: unknown long option: %s (%d)\n",
                 argv[0], long_options[option_index].name, option_index);
        exit (EXIT_FAILURE);
      }
      break;

    case 'f':
      format = optarg;
      break;

    case 'u':
      euid = parseuser (optarg, argv[0]);
      break;

    case 'g':
      egid = parsegroup (optarg, argv[0]);
      break;

    case 'k':
      whitelist = optarg;
      break;

    case 'v':
      verbose++;
      break;

    case 'V':
      printf (PACKAGE_NAME " " PACKAGE_VERSION "\n");
      exit (EXIT_SUCCESS);

    default:
      usage (stderr, argv[0]);
      exit (EXIT_FAILURE);
    }
  }

  /* We need to set the real, not effective, uid here to work round a
   * misfeature in bash. bash will automatically reset euid to uid when
   * invoked. As shell is used in places by febootstrap-supermin-helper, this
   * results in code running with varying privilege. */
  uid_t uid = getuid ();
  gid_t gid = getgid ();

  if (uid != euid || gid != egid) {
    if (uid != 0) {
      fprintf (stderr, "The -u and -g options require root privileges.\n");
      usage (stderr, argv[0]);
      exit (EXIT_FAILURE);
    }

    /* Need to become root first because setgid and setuid require it */
    if (seteuid (0) == -1) {
        perror ("seteuid");
        exit (EXIT_FAILURE);
    }

    /* Set gid and uid to command-line parameters */
    if (setgid (egid) == -1) {
      perror ("setgid");
      exit (EXIT_FAILURE);
    }

    /* Kill supplemental groups from parent process (RHBZ#902476). */
    if (setgroups (1, &egid) == -1) {
      perror ("setgroups");
      exit (EXIT_FAILURE);
    }

    if (setuid (euid) == -1) {
      perror ("setuid");
      exit (EXIT_FAILURE);
    }
  }

  /* Select the correct writer module. */
  struct writer *writer;
  int nr_outputs;

  if (strcmp (format, "cpio") == 0) {
    writer = &cpio_writer;
    nr_outputs = 2;             /* kernel and appliance (== initrd) */
  }
  else if (strcmp (format, "ext2") == 0) {
    writer = &ext2_writer;
    nr_outputs = 3;             /* kernel, initrd, appliance */
  }
  else if (strcmp (format, "checksum") == 0) {
    writer = &checksum_writer;
    nr_outputs = 0;             /* (none) */
  }
  else {
    fprintf (stderr,
             "%s: incorrect output format (-f): must be cpio|ext2|checksum\n",
             argv[0]);
    exit (EXIT_FAILURE);
  }

  /* [optind .. optind+nr_inputs-1] hostcpu [argc-nr_outputs-1 .. argc-1]
   * <----     nr_inputs      ---->    1    <----    nr_outputs     ---->
   */
  char **inputs = &argv[optind];
  int nr_inputs = argc - nr_outputs - 1 - optind;
  char **outputs = &argv[optind+nr_inputs+1];
  /*assert (outputs [nr_outputs] == NULL);
    assert (inputs [nr_inputs + 1 + nr_outputs] == NULL);*/

  if (nr_inputs < 1) {
    fprintf (stderr, "%s: not enough files specified on the command line\n",
             argv[0]);
    exit (EXIT_FAILURE);
  }

  /* See: https://bugzilla.redhat.com/show_bug.cgi?id=558593 */
  const char *hostcpu = outputs[-1];

  /* Output files. */
  const char *kernel = NULL, *initrd = NULL, *appliance = NULL;
  if (nr_outputs > 0)
    kernel = outputs[0];
  if (nr_outputs > 1)
    initrd = appliance = outputs[1];
  if (nr_outputs > 2)
    appliance = outputs[2];

  if (verbose) {
    print_timestamped_message ("whitelist = %s, "
                               "host_cpu = %s, "
                               "kernel = %s, "
                               "initrd = %s, "
                               "appliance = %s",
                               whitelist ? : "(not specified)",
                               hostcpu, kernel, initrd, appliance);
    int i;
    for (i = 0; i < nr_inputs; ++i)
      print_timestamped_message ("inputs[%d] = %s", i, inputs[i]);
  }

  /* Remove the output files if they exist. */
  if (kernel)
    unlink (kernel);
  if (initrd)
    unlink (initrd);
  if (appliance && initrd != appliance)
    unlink (appliance);

  /* Create kernel output file. */
  const char *modpath = create_kernel (hostcpu, kernel);

  if (verbose)
    print_timestamped_message ("finished creating kernel");

  /* Create the appliance. */
  create_appliance (hostcpu, inputs, nr_inputs, whitelist, modpath,
                    initrd, appliance, writer);

  if (verbose)
    print_timestamped_message ("finished creating appliance");

  exit (EXIT_SUCCESS);
}
