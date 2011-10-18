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

(** Generic package handler code. *)

type package_handler = {
  ph_detect : unit -> bool;
  (** Detect if the current system uses this package manager.  This is
      called in turn on each package handler, until one returns [true]. *)

  ph_init : unit -> unit;
  (** After a package handler is selected, this function is called
      which can optionally do any initialization that is required.
      This is only called on the package handler if it has returned
      [true] from {!ph_detect}. *)

  ph_resolve_dependencies_and_download : string list -> string list;
  (** [ph_resolve_dependencies_and_download pkgs]
      Take a list of package names, and using the package manager
      resolve those to a list of all the packages that are required
      including dependencies.  Download the full list of packages and
      dependencies into a tmpdir.  Return the list of full filenames.

      Note this should also process the [excludes] list. *)

  ph_list_files : string -> (string * file_type) list;
  (** [ph_list_files pkg] lists the files and file metadata in the
      package called [pkg] (a package file). *)

  ph_get_file_from_package : string -> string -> string;
  (** [ph_get_file_from_package pkg file] extracts the
      single named file [file] from [pkg].  The path of the
      extracted file is returned. *)
}

(* These file types are inspired by the metadata specifically
 * stored by RPM.  We should look at what other package formats
 * can use too.
 *)
and file_type = {
  ft_dir : bool;               (** Is a directory. *)
  ft_config : bool;            (** Is a configuration file. *)
  ft_ghost : bool;             (** Is a ghost (created empty) file. *)
  ft_mode : int;               (** File mode. *)
  ft_size : int;	       (** File size. *)
}

val register_package_handler : string -> package_handler -> unit
  (** Register a package handler. *)

val check_system : unit -> unit
  (** Check which package manager this system uses. *)

val get_package_handler : unit -> package_handler
  (** Get the selected package manager for this system. *)

val get_package_handler_name : unit -> string
  (** Get the name of the selected package manager for this system. *)
