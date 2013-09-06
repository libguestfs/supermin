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
#include <stdbool.h>
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

static const char *options = "f:g:k:o:u:vV";
static const struct option long_options[] = {
  { "help", 0, 0, HELP_OPTION },
  { "copy-kernel", 0, 0, 0 },
  { "dtb", required_argument, 0, 0 },
  { "format", required_argument, 0, 'f' },
  { "group", required_argument, 0, 'g' },
  { "host-cpu", required_argument, 0, 0 },
  { "kmods", required_argument, 0, 'k' },
  { "output-appliance", required_argument, 0, 0 },
  { "output-dtb", required_argument, 0, 0 },
  { "output-initrd", required_argument, 0, 0 },
  { "output-kernel", required_argument, 0, 0 },
  { "user", required_argument, 0, 'u' },
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
           "  %s [-f cpio|ext2] -o outputdir input [input...]\n"
           "or:\n"
           "  %s [-f cpio|ext2] --output-kernel kernel \\\n"
           "  [--output-dtb dtb] --output-initrd initrd \\\n"
           "  [--output-appliance appliance] input [input...]\n"
           "or:\n"
           "  %s -f checksum input [input ...]\n"
           "or:\n"
           "  %s --help\n"
           "  %s --version\n"
           "\n"
           "This program is used to build the full appliance from the supermin appliance.\n"
           "\n"
           "Options:\n"
           "  --help\n"
           "       Display this help text and exit.\n"
           "  --copy-kernel\n"
           "       Copy the kernel & device tree instead of symlinking to it.\n"
           "  --dtb wildcard\n"
           "       Search for a device tree matching wildcard.\n"
           "  -f cpio|ext2|checksum | --format cpio|ext2|checksum\n"
           "       Specify output format (default: cpio).\n"
           "  --host-cpu cpu\n"
           "       Host CPU type (default: " host_cpu ").\n"
           "  -k file | --kmods file\n"
           "       Specify kernel module whitelist.\n"
           "  -o outputdir\n"
           "       Write output to outputdir/kernel etc.\n"
           "  --output-appliance path\n"
           "       Write appliance to path (overrides -o).\n"
           "  --output-dtb path\n"
           "       Write device tree to path (overrides -o).\n"
           "  --output-initrd path\n"
           "       Write initrd to path (overrides -o).\n"
           "  --output-kernel path\n"
           "       Write kernel to path (overrides -o).\n"
           "  -u user | --user user\n"
           "  -g group | --group group\n"
           "       The user name or uid, and group name or gid the appliance will\n"
           "       run as. Use of these options requires root privileges.\n"
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

  /* For the reason this was originally added, see
   * https://bugzilla.redhat.com/show_bug.cgi?id=558593
   */
  const char *hostcpu = host_cpu;

  /* Output files. */
  char *kernel = NULL, *dtb = NULL, *initrd = NULL, *appliance = NULL;
  const char *output_dir = NULL;

  /* Device tree wildcard (--dtb argument). */
  const char *dtb_wildcard = NULL;

  uid_t euid = geteuid ();
  gid_t egid = getegid ();

  bool old_style = true;

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
      }
      else if (strcmp (long_options[option_index].name, "dtb") == 0) {
        dtb_wildcard = optarg;
        old_style = false;      /* --dtb + old-style wouldn't work anyway */
      }
      else if (strcmp (long_options[option_index].name, "host-cpu") == 0) {
        hostcpu = optarg;
        old_style = false;
      }
      else if (strcmp (long_options[option_index].name, "output-kernel") == 0) {
        kernel = optarg;
        old_style = false;
      }
      else if (strcmp (long_options[option_index].name, "output-dtb") == 0) {
        dtb = optarg;
        old_style = false;
      }
      else if (strcmp (long_options[option_index].name, "output-initrd") == 0) {
        initrd = optarg;
        old_style = false;
      }
      else if (strcmp (long_options[option_index].name, "output-appliance") == 0) {
        appliance = optarg;
        old_style = false;
      }
      else {
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

    case 'o':
      output_dir = optarg;
      old_style = false;
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

  /* Select the correct writer module. */
  struct writer *writer;
  bool needs_kernel;
  bool needs_initrd;
  bool needs_appliance;

  bool needs_dtb = dtb_wildcard != NULL;

  if (strcmp (format, "cpio") == 0) {
    writer = &cpio_writer;
    needs_kernel = true;
    needs_initrd = true;
    needs_appliance = false;
  }
  else if (strcmp (format, "ext2") == 0) {
    writer = &ext2_writer;
    needs_kernel = true;
    needs_initrd = true;
    needs_appliance = true;
  }
  else if (strcmp (format, "checksum") == 0) {
    writer = &checksum_writer;
    needs_kernel = false;
    needs_initrd = false;
    needs_appliance = false;
  }
  else {
    fprintf (stderr,
             "%s: incorrect output format (-f): must be cpio|ext2|checksum\n",
             argv[0]);
    exit (EXIT_FAILURE);
  }

  char **inputs = &argv[optind];
  int nr_inputs;

  /* Old-style arguments? */
  if (old_style) {
    int nr_outputs;

    if (strcmp (format, "cpio") == 0)
      nr_outputs = 2;             /* kernel and appliance (== initrd) */
    else if (strcmp (format, "ext2") == 0)
      nr_outputs = 3;             /* kernel, initrd, appliance */
    else if (strcmp (format, "checksum") == 0)
      nr_outputs = 0;             /* (none) */
    else
      abort ();

    /* [optind .. optind+nr_inputs-1] hostcpu [argc-nr_outputs-1 .. argc-1]
     * <----     nr_inputs      ---->    1    <----    nr_outputs     ---->
     */
    nr_inputs = argc - nr_outputs - 1 - optind;
    char **outputs = &argv[optind+nr_inputs+1];
    /*assert (outputs [nr_outputs] == NULL);
      assert (inputs [nr_inputs + 1 + nr_outputs] == NULL);*/

    if (nr_outputs > 0)
      kernel = outputs[0];
    if (nr_outputs > 1)
      initrd = outputs[1];
    if (nr_outputs > 2)
      appliance = outputs[2];
  }
  /* New-style?  Check all outputs were defined. */
  else {
    if (needs_kernel && !kernel) {
      if (!output_dir) {
      no_output_dir:
        fprintf (stderr, "%s: use -o to specify output directory or --output-[kernel|dtb|initrd|appliance]\n", argv[0]);
        exit (EXIT_FAILURE);
      }
      if (asprintf (&kernel, "%s/kernel", output_dir) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
    }

    if (needs_dtb && !dtb) {
      if (!output_dir)
        goto no_output_dir;
      if (asprintf (&dtb, "%s/dtb", output_dir) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
    }

    if (needs_initrd && !initrd) {
      if (!output_dir)
        goto no_output_dir;
      if (asprintf (&initrd, "%s/initrd", output_dir) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
    }

    if (needs_appliance && !appliance) {
      if (!output_dir)
        goto no_output_dir;
      if (asprintf (&appliance, "%s/appliance", output_dir) == -1) {
        perror ("asprintf");
        exit (EXIT_FAILURE);
      }
    }

    nr_inputs = argc - optind;
  }

  if (nr_inputs < 1) {
    fprintf (stderr, "%s: not enough files specified on the command line\n",
             argv[0]);
    exit (EXIT_FAILURE);
  }

  if (verbose) {
    print_timestamped_message ("whitelist = %s",
                               whitelist ? : "(not specified)");
    print_timestamped_message ("host_cpu = %s", hostcpu);
    print_timestamped_message ("dtb_wildcard = %s",
                               dtb_wildcard ? : "(not specified)");
    print_timestamped_message ("inputs:");
    int i;
    for (i = 0; i < nr_inputs; ++i)
      print_timestamped_message ("inputs[%d] = %s", i, inputs[i]);
    print_timestamped_message ("outputs:");
    print_timestamped_message ("kernel = %s", kernel ? : "(none)");
    print_timestamped_message ("dtb = %s", dtb ? : "(none)");
    print_timestamped_message ("initrd = %s", initrd ? : "(none)");
    print_timestamped_message ("appliance = %s", appliance ? : "(none)");
  }

  /* We need to set the real, not effective, uid here to work round a
   * misfeature in bash. bash will automatically reset euid to uid when
   * invoked. As shell is used in places by supermin-helper, this
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

  /* Remove the output files if they exist. */
  if (kernel)
    unlink (kernel);
  if (dtb)
    unlink (dtb);
  if (initrd)
    unlink (initrd);
  if (appliance)
    unlink (appliance);

  /* Create kernel output file. */
  const char *modpath = create_kernel (hostcpu, kernel, dtb_wildcard, dtb);

  if (verbose)
    print_timestamped_message ("finished creating kernel");

  /* Create the appliance. */
  create_appliance (hostcpu, inputs, nr_inputs, whitelist, modpath,
                    initrd, appliance, writer);

  if (verbose)
    print_timestamped_message ("finished creating appliance");

  exit (EXIT_SUCCESS);
}
