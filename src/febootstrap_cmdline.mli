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

(** Command line parsing. *)

val debug : ('a, unit, string, unit) format4 -> 'a
  (** Print string (like printf), but only if --verbose was given on
      the command line. *)

val excludes : Str.regexp list
  (** List of package regexps to exclude. *)

val names_mode : bool
  (** True if [--names] was given on the command line (otherwise
      {!packages} is a list of filenames). *)

val outputdir : string
  (** Output directory. *)

val packages : string list
  (** List of packages or package names as supplied on the command line. *)

val save_temps : bool
  (** True if [--save-temps] was given on the command line. *)

val use_installed : bool
  (** True if [--use-installed] was given on the command line *)

val verbose : bool
  (** True if [--verbose] was given on the command line.
      See also {!debug}. *)

val warnings : bool
  (** If true, print warnings.  [--no-warnings] sets this to false. *)

val packager_config : string option
  (** Package manager configuration file. *)
