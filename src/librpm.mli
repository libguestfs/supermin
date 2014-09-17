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

val rpm_is_available : unit -> bool

val rpm_version : unit -> string

type t

exception Multiple_matches of int

val rpm_open : ?debug:int -> t
val rpm_close : t -> unit

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
val rpm_pkg_requires : t -> string -> string array
val rpm_pkg_whatprovides : t -> string -> string array
val rpm_pkg_filelist : t -> string -> rpmfile_t array
