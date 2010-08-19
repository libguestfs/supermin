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

#include "error.h"

#include "helper.h"

struct timeval start_t;
int verbose = 0;

static const char *format = "cpio";

enum { HELP_OPTION = CHAR_MAX + 1 };

static const char *options = "f:k:vV";
static const struct option long_options[] = {
  { "help", 0, 0, HELP_OPTION },
  { "format", required_argument, 0, 'f' },
  { "kmods", required_argument, 0, 'k' },
  { "verbose", 0, 0, 'v' },
  { "version", 0, 0, 'V' },
  { 0, 0, 0, 0 }
};

static void
usage (const char *progname)
{
  printf ("%s: build the supermin appliance on the fly\n"
          "\n"
          "Usage:\n"
          "  %s [-options] inputs [...] host_cpu kernel initrd\n"
          "  %s -f ext2 inputs [...] host_cpu kernel initrd appliance\n"
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
          "  -f cpio | --format cpio\n"
          "       Specify output format (default: cpio).\n"
          "  -k file | --kmods file\n"
          "       Specify kernel module whitelist.\n"
          "  --verbose | -v\n"
          "       Enable verbose messages (give multiple times for more verbosity).\n"
          "  --version | -V\n"
          "       Display version number and exit.\n",
          progname, progname, progname, progname, progname);
}

int
main (int argc, char *argv[])
{
  /* First thing: start the clock. */
  gettimeofday (&start_t, NULL);

  const char *whitelist = NULL;

  /* Command line arguments. */
  for (;;) {
    int c = getopt_long (argc, argv, options, long_options, NULL);
    if (c == -1) break;

    switch (c) {
    case HELP_OPTION:
      usage (argv[0]);
      exit (EXIT_SUCCESS);

    case 'f':
      format = optarg;
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
      usage (argv[0]);
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
  else {
    fprintf (stderr, "%s: incorrect output format (-f): must be cpio\n",
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
  const char *kernel = outputs[0];
  const char *initrd;
  const char *appliance;
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
  unlink (kernel);
  unlink (initrd);
  if (initrd != appliance)
    unlink (appliance);

  /* Create kernel output file. */
  const char *modpath;
  modpath = create_kernel (hostcpu, kernel);

  if (verbose)
    print_timestamped_message ("finished creating kernel");

  /* Create the appliance. */
  create_appliance (inputs, nr_inputs, whitelist, modpath,
                    initrd, appliance, writer);

  if (verbose)
    print_timestamped_message ("finished creating appliance");

  exit (EXIT_SUCCESS);
}
