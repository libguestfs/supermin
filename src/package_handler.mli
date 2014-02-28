(* supermin 5
 * Copyright (C) 2009-2014 Red Hat Inc.
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

(** {2 Package handlers.} *)

type package = int

module PackageSet : sig
  type elt = package
  type t
  val empty : t
  val is_empty : t -> bool
  val mem : elt -> t -> bool
  val add : elt -> t -> t
  val singleton : elt -> t
  val remove : elt -> t -> t
  val union : t -> t -> t
  val inter : t -> t -> t
  val diff : t -> t -> t
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val subset : t -> t -> bool
  val iter : (elt -> unit) -> t -> unit
  val fold : (elt -> 'a -> 'a) -> t -> 'a -> 'a
  val for_all : (elt -> bool) -> t -> bool
  val exists : (elt -> bool) -> t -> bool
  val filter : (elt -> bool) -> t -> t
  val partition : (elt -> bool) -> t -> t * t
  val cardinal : t -> int
  val elements : t -> elt list
  val min_elt : t -> elt
  val max_elt : t -> elt
  val choose : t -> elt
  val split : elt -> t -> t * bool * t
end

val package_set_of_list : package list -> PackageSet.t

(** Package handler settings, passed to [ph_init] function. *)
type settings = {
  debug : int;                         (** Debugging level (-v option). *)
  tmpdir : string;
  (** A scratch directory, where the package handler may write any
      files or directories it needs.  The directory exists already, so
      does not need to be created.  It is deleted automatically when
      the program exits. *)
  packager_config : string option;
  (** The --packager-config command line option, if present. *)
}

val no_settings : settings
(** An empty settings struct. *)

(** Files (also directories and other filesystem objects) that are
    part of a particular package.  Note that the package is always
    installed when we query it, so to find out things like the file
    type, size and mode you just need to [lstat file.ft_path]. *)
type file = {
  ft_path : string;
  (** File path. *)

  ft_config : bool;
  (** Flag to indicate this is a configuration file.  In some package
      managers (RPM) this is stored in package metadata.  In others
      (dpkg) we guess it based on the filename. *)
}

(** Package handlers are modules that implement this structure and
    call {!register_package_handler}. *)
type package_handler = {
  ph_detect : unit -> bool;
  (** The package handler should return true if the system uses this
      package manager. *)

  ph_init : settings -> unit;
  (** This is called when this package handler is chosen and
      initializes.  The [settings] parameter is a struct of general
      settings and configuration. *)

  ph_package_of_string : string -> package option;
  (** Convert a string (from user input) into a package object.  If
      the package is not installed or the string is otherwise
      incorrect this returns [None]. *)

  ph_package_to_string : package -> string;
  (** Convert package back to a printable string.  {b Only} use this
      for debugging and printing errors.  Use {!ph_package_name} for a
      reproducible name that can be written to packages file. *)

  ph_package_name : package -> string;
  (** Return the name of the package, for writing to packagelist. *)

  ph_get_package_database_mtime : unit -> float;
  (** Return the last modification time of the package database.

      If not supported, then a package handler can return [0.0] here.
      However that will mean that supermin will rebuild the appliance
      every time it is run, even when the --if-newer option is
      used. *)

  ph_get_requires : ph_get_requires;
  (** Given a single installed package or set of packages, return the
      names of the installed packages that are dependencies of this
      package.

      {b Note} the returned set must also contain the original package.

      The package handler can either implement a function to resolve a
      single package name ([PHGetRequires]), or (more efficiently)
      resolve a set of packages ([PHGetAllRequires]). *)

  ph_get_files : ph_get_files;
  (** Given a single installed package or set of packages, list out
      the files in that package (including package management
      metadata).

      The package handler can either implement a function to list a
      single package ([PHGetFiles]), or (more efficiently) list all
      files in a set of packages ([PHGetAllFiles]). *)

  ph_download_package : ph_download_package;
  (** [ph_download_package package dir] downloads the named package
      from the repository, and unpacks it in the given [dir].

      The package handler can either implement a function to download
      a single package ([PHDownloadPackage]), or (more efficiently)
      list all files in a set of packages ([PHDownloadAllPackages]).

      When [--use-installed] option is used, this will not be called. *)
}
and ph_get_requires =
| PHGetRequires of (package -> PackageSet.t)
| PHGetAllRequires of (PackageSet.t -> PackageSet.t)
and ph_get_files =
| PHGetFiles of (package -> file list)
| PHGetAllFiles of (PackageSet.t -> file list)
and ph_download_package =
| PHDownloadPackage of (package -> string -> unit)
| PHDownloadAllPackages of (PackageSet.t -> string -> unit)

(** Package handlers could use these memoization functions to convert
    from the {!package} type to an internal struct and back again, or
    they can implement their own. *)
val get_memo_functions : unit -> (package -> 'a) * ('a -> package)

(** At program start-up, all package handlers register themselves here. *)
val register_package_handler : string -> package_handler -> unit

val check_system : settings -> unit

val get_package_handler : unit -> package_handler

val get_package_handler_name : unit -> string

val get_all_requires : PackageSet.t -> PackageSet.t
val get_files : package -> file list
(*val get_all_files : PackageSet.t -> file list*)
val download_all_packages : PackageSet.t -> string -> unit
