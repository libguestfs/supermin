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

open Unix
open Printf

open Utils

type package = int

module PackageSet = Set.Make (
  struct
    type t = package
    let compare = compare
  end
)

let package_set_of_list pkgs =
  List.fold_right PackageSet.add pkgs PackageSet.empty

type settings = {
  debug : int;
  tmpdir : string;
  packager_config : string option;
}

let no_settings =
  { debug = 0; tmpdir = "/nowhere"; packager_config = None; }

type file = {
  ft_path : string;
  ft_source_path : string;
  ft_config : bool;
}

let file_source file =
  try
    if (lstat file.ft_source_path).st_kind = S_REG then
      file.ft_source_path
    else
      file.ft_path
  with Unix_error _ -> file.ft_path

type package_handler = {
  ph_detect : unit -> bool;
  ph_init : settings -> unit;
  ph_fini : unit -> unit;
  ph_package_of_string : string -> package option;
  ph_package_to_string : package -> string;
  ph_package_name : package -> string;
  ph_get_package_database_mtime : unit -> float;
  ph_get_requires : ph_get_requires;
  ph_get_files : ph_get_files;
  ph_download_package : ph_download_package;
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

(* Suggested memoization functions. *)
let get_memo_functions () =
  let id = ref 0 in
  let h1 = Hashtbl.create 13 and h2 = Hashtbl.create 13 in
  let internal_of_pkg pkg =
    try Hashtbl.find h1 pkg with Not_found -> assert false
  in
  let pkg_of_internal internal =
    try Hashtbl.find h2 internal
    with Not_found ->
      let id = incr id; !id in
      Hashtbl.add h2 internal id;
      Hashtbl.add h1 id internal;
      id
  in
  internal_of_pkg, pkg_of_internal

let handlers = ref []
let register_package_handler system packager ph =
  handlers := (system, packager, ph) :: !handlers

let list_package_handlers () =
  List.iter (
    fun (system, packager, ph) ->
      let detected = ph.ph_detect () in
      printf "%s/%s\t%s\n"
        system packager (if detected then "detected" else "not-detected")
  ) !handlers

let handler = ref None

let check_system settings =
  try
    let (_, _, ph) as h =
      List.find (fun (_, _, ph) -> ph.ph_detect ()) !handlers in
    handler := Some h;
    ph.ph_init settings
  with Not_found ->
    error "\
could not detect package manager used by this system or distro.

If this is a new Linux distro, or not Linux, or a Linux distro that uses
an unusual packaging format then you may need to port supermin.  If
you are expecting that supermin should work on this system or distro
then it may be that the package detection code is not working.

To list which package handlers are compiled into this version of
supermin, do:

  supermin --list-drivers
"

let rec get_package_handler () =
  match !handler with
  | Some (_, _, ph) -> ph
  | None -> assert false

let rec get_package_handler_name () =
  match !handler with
  | Some (system, packager, _) -> sprintf "%s/%s" system packager
  | None -> assert false

let package_handler_shutdown () =
  let ph = get_package_handler () in
  ph.ph_fini ()

let get_all_requires pkgs =
  let ph = get_package_handler () in
  match ph.ph_get_requires with
  | PHGetRequires f ->
    PackageSet.fold (fun pkg -> PackageSet.union (f pkg)) pkgs PackageSet.empty
  | PHGetAllRequires f -> f pkgs

let get_files pkg =
  let ph = get_package_handler () in
  match ph.ph_get_files with
  | PHGetFiles f -> f pkg
  | PHGetAllFiles f -> f (PackageSet.singleton pkg)

let get_all_files pkgs =
  let ph = get_package_handler () in
  match ph.ph_get_files with
  | PHGetFiles f ->
    PackageSet.fold (fun pkg xs -> let files = f pkg in files @ xs) pkgs []
  | PHGetAllFiles f -> f pkgs

let download_all_packages pkgs dir =
  let ph = get_package_handler () in
  match ph.ph_download_package with
  | PHDownloadPackage f ->
    PackageSet.iter (fun pkg -> f pkg dir) pkgs
  | PHDownloadAllPackages f -> f pkgs dir
