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

open Unix
open Printf

open Supermin_utils
open Supermin_cmdline

type package_handler = {
  ph_detect : unit -> bool;
  ph_init : unit -> unit;
  ph_resolve_dependencies_and_download : string list -> mode -> string list;
  ph_list_files : string -> (string * file_type) list;
  ph_get_file_from_package : string -> string -> string
}
and file_type = {
  ft_dir : bool;
  ft_config : bool;
  ft_ghost : bool;
  ft_mode : int;
  ft_size : int;
}

let tmpdir = tmpdir ()

let handlers = ref []

let register_package_handler name ph =
  handlers := (name, ph) :: !handlers

let handler = ref None

let rec check_system () =
  try
    handler := Some (
      List.find (
        fun (_, ph) ->
          ph.ph_detect ()
      ) !handlers
    );
    (get_package_handler ()).ph_init ()
  with Not_found ->
    eprintf "\
supermin: could not detect package manager used by this system or distro.

If this is a new Linux distro, or not Linux, or a Linux distro that uses
an unusual packaging format then you may need to port supermin.  If
you are expecting that supermin should work on this system or distro
then it may be that the package detection code is not working.
";
    exit 1

and get_package_handler () =
  match !handler with
  | Some (_, ph) -> ph
  | None ->
      check_system ();
      get_package_handler ()

and get_package_handler_name () =
  match !handler with
  | Some (name, _) -> name
  | None ->
      check_system ();
      get_package_handler_name ()
