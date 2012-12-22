(* febootstrap 3
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

open Printf

let excludes = ref []
let names_mode = ref false
let outputdir = ref "."
let packages = ref []
let save_temps = ref false
let use_installed = ref false
let verbose = ref false
let warnings = ref true
let packager_config = ref None

let print_version () =
  printf "%s %s\n" Config.package_name Config.package_version;
  exit 0

let add_exclude re =
  excludes := Str.regexp re :: !excludes

let set_packager_config str =
  packager_config := Some str

let argspec = Arg.align [
  "--exclude", Arg.String add_exclude,
    "regexp Exclude packages matching regexp";
  "--names", Arg.Set names_mode,
    " Specify set of root package names on command line";
  "--no-warnings", Arg.Clear warnings,
    " Suppress warnings";
  "-o", Arg.Set_string outputdir,
    "outputdir Set output directory (default: \".\")";
  "--packager-config", Arg.String set_packager_config,
    "file Set alternate package manager configuration file";
  "--save-temp", Arg.Set save_temps,
    " Don't delete temporary files and directories on exit.";
  "--save-temps", Arg.Set save_temps,
    " Don't delete temporary files and directories on exit.";
  "--use-installed", Arg.Set use_installed,
    " Inspect already installed packages for determining contents.";
  "-v", Arg.Set verbose,
    " Enable verbose output";
  "--verbose", Arg.Set verbose,
    " Enable verbose output";
  "-V", Arg.Unit print_version,
    " Print package name and version, and exit";
  "--version", Arg.Unit print_version,
    " Print package name and version, and exit";
  "--yum-config", Arg.String set_packager_config,
    "file Deprecated alias for `--packager-config file'";
]
let anon_fn str =
  packages := str :: !packages

let usage_msg =
  "\
febootstrap - bootstrapping tool for creating supermin appliances
Copyright (C) 2009-2010 Red Hat Inc.

Usage:
 febootstrap [-o OUTPUTDIR] --names LIST OF PKGS ...
 febootstrap [-o OUTPUTDIR] PKG FILE NAMES ...

For full instructions see the febootstrap(8) man page.

Options:\n"

let () =
  Arg.parse argspec anon_fn usage_msg;
  if !packages = [] then (
    eprintf "febootstrap: no packages listed on the command line\n";
    exit 1
  )

let excludes = List.rev !excludes
let names_mode = !names_mode
let outputdir = !outputdir
let packages = List.rev !packages
let save_temps = !save_temps
let use_installed = !use_installed
let verbose = !verbose
let warnings = !warnings
let packager_config = !packager_config

let debug fs = ksprintf (fun str -> if verbose then print_endline str) fs
