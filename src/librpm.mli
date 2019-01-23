(* supermin 5
 * Copyright (C) 2014 Red Hat Inc.
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

(** Wrappers around [librpm] functions. *)

val rpm_is_available : unit -> bool
(** Returns [true] iff librpm is supported.  If this returns [false],
    then all other functions will abort. *)

val rpm_version : unit -> string
(** The linked version of librpm. *)

val rpm_vercmp : string -> string -> int
(** Compare two RPM version strings using RPM version compare rules. *)

type t
(** The librpm handle. *)

exception Multiple_matches of string * int

val rpm_open : ?debug:int -> t
(** Open the librpm (transaction set) handle. *)
val rpm_close : t -> unit
(** Explicitly close the handle.  The handle can also be closed by
    the garbage collector if it becomes unreachable. *)

type rpm_t = {
  name : string;
  epoch : int;
  version : string;
  release : string;
  arch : string;
}

type rpmfile_t = {
  filepath : string;
  filetype : rpmfiletype_t;
} and rpmfiletype_t =
  | FileNormal
  | FileConfig

val rpm_installed : t -> string -> rpm_t array
(** Return the list of packages matching the name
    (similar to [rpm -q name]). *)

val rpm_pkg_requires : t -> string -> string array
(** Return the requires of a package (similar to [rpm -qR]). *)

val rpm_pkg_whatprovides : t -> string -> string array
(** Return what package(s) provide a particular requirement
    (similar to [rpm -q --whatprovides]). *)

val rpm_pkg_filelist : t -> string -> rpmfile_t array
(** Return the list of files contained in a package, and attributes of
    those files (similar to [rpm -ql]). *)
