(* supermin 4
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

open Printf

type mode =                             (* --names/--names-only flag *)
  | PkgFiles                            (* no flag *)
  | PkgNames                            (* --names *)
  | PkgNamesOnly                        (* --names-only *)

let excludes = ref []
let mode = ref PkgFiles
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

let set_packager_config filename =
  (* Need to check that the file exists, and make the path absolute. *)
  let filename =
    if Filename.is_relative filename then
      Filename.concat (Sys.getcwd ()) filename
    else filename in
  if not (Sys.file_exists filename) then (
    eprintf "supermin: --packager-config: %s: file does not exist\n"
      filename;
    exit 1
  );

  packager_config := Some filename

let error_supermin_4 () =
  eprintf "supermin: *** error: This is supermin version 4.\n";
  eprintf "supermin: *** It looks like you are looking for supermin version >= 5.\n";
  eprintf "\n";
  eprintf "This version of supermin will not work.  You need to update to a\n";
  eprintf "newer version.\n";
  eprintf "\n";
  exit 1

let argspec = Arg.align [
  "--exclude", Arg.String add_exclude,
    "regexp Exclude packages matching regexp";
  "--names", Arg.Unit (fun () -> mode := PkgNames),
    " Specify set of root package names on command line";
  "--names-only", Arg.Unit (fun () -> mode := PkgNamesOnly),
    " Specify exact set of package names on command line";
  "--no-warnings", Arg.Clear warnings,
    " Suppress warnings";
  "-o", Arg.Set_string outputdir,
    "outputdir Set output directory (default: \".\")";
  "--packager-config", Arg.String set_packager_config,
    "file Set alternate package manager configuration file";
  "--save-temp", Arg.Set save_temps,
    " Don't delete temporary files and directories on exit";
  "--save-temps", Arg.Set save_temps,
    " Don't delete temporary files and directories on exit";
  "--use-installed", Arg.Set use_installed,
    " Use already installed packages for package contents";
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
  "--build", Arg.Unit error_supermin_4,
    " Give an error for people needing supermin 5";
  "--prepare", Arg.Unit error_supermin_4,
    " Give an error for people needing supermin 5";
]
let anon_fn str =
  packages := str :: !packages

let usage_msg =
  "\
supermin - tool for creating supermin appliances
Copyright (C) 2009-2013 Red Hat Inc.

Usage:
 supermin [-o OUTPUTDIR] --names LIST OF PKGS ...
 supermin [-o OUTPUTDIR] PKG FILE NAMES ...

For full instructions see the supermin(1) man page.

Options:\n"

let () =
  Arg.parse argspec anon_fn usage_msg;
  if !packages = [] then (
    eprintf "supermin: no packages listed on the command line\n";
    exit 1
  )

let excludes = List.rev !excludes
let mode = !mode
let outputdir = !outputdir
let packages = List.rev !packages
let save_temps = !save_temps
let use_installed = !use_installed
let verbose = !verbose
let warnings = !warnings
let packager_config = !packager_config

let debug fs = ksprintf (fun str -> if verbose then print_endline str) fs
