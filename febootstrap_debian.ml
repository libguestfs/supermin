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

(* Debian support. *)

open Unix
open Printf

open Febootstrap_package_handlers
open Febootstrap_utils
open Febootstrap_cmdline

(* Create a temporary directory for use by all the functions in this file. *)
let tmpdir = tmpdir ()

let debian_detect () =
  file_exists "/etc/debian_version" &&
    Config.aptitude <> "no" && Config.dpkg <> "no"

let debian_resolve_dependencies_and_download names =
  let cmd =
    sprintf "apt-cache depends --recurse -i %s | grep -v '^[<[:space:]]'"
      (String.concat " " (List.map Filename.quote names)) in
  let pkgs = run_command_get_lines cmd in

  (* Exclude packages matching [--exclude] regexps on the command line. *)
  let pkgs =
    List.filter (
      fun name ->
        not (List.exists (fun re -> Str.string_match re name 0) excludes)
    ) pkgs in

  (* Download the packages. *)
  let cmd =
    sprintf "cd %s && aptitude download %s"
      (Filename.quote tmpdir)
      (String.concat " " (List.map Filename.quote pkgs)) in
  run_command cmd;

  (* Find out what aptitude downloaded. *)
  let files = Sys.readdir tmpdir in

  let pkgs = List.map (
    fun pkg ->
      (* Look for 'pkg_*.deb' in the list of files. *)
      let pre = pkg ^ "_" in
      let r = ref "" in
      try
	for i = 0 to Array.length files - 1 do
	  if string_prefix pre files.(i) then (
	    r := files.(i);
	    files.(i) <- "";
	    raise Exit
	  )
	done;
	eprintf "febootstrap: aptitude: error: no file was downloaded corresponding to package %s\n" pkg;
	exit 1
      with
	  Exit -> !r
  ) pkgs in

  List.sort compare pkgs

let debian_list_files pkg =
  debug "unpacking %s ..." pkg;

  (* We actually need to extract the file in order to get the
   * information about modes etc.
   *)
  let pkgdir = tmpdir // pkg ^ ".d" in
  mkdir pkgdir 0o755;
  let cmd =
    sprintf "dpkg-deb --fsys-tarfile %s | (cd %s && tar xf -)"
      (tmpdir // pkg) pkgdir in
  run_command cmd;

  let cmd = sprintf "cd %s && find ." pkgdir in
  let lines = run_command_get_lines cmd in

  let files = List.map (
    fun path ->
      assert (path.[0] = '.');
      (* No leading '.' *)
      let path =
	if path = "." then "/"
	else String.sub path 1 (String.length path - 1) in

      (* Find out what it is and get the canonical filename. *)
      let statbuf = lstat (pkgdir // path) in
      let is_dir = statbuf.st_kind = S_DIR in

      (* No per-file metadata like in RPM, but we can synthesize it
       * from the path.
       *)
      let config = statbuf.st_kind = S_REG && string_prefix path "/etc/" in

      let mode = statbuf.st_perm in

      (path, { ft_dir = is_dir; ft_config = config; ft_mode = mode;
	       ft_ghost = false })
  ) lines in

  files

(* Easy because we already unpacked the archive above. *)
let debian_get_file_from_package pkg file =
  tmpdir // pkg ^ ".d" // file

let () =
  let ph = {
    ph_detect = debian_detect;
    ph_resolve_dependencies_and_download =
      debian_resolve_dependencies_and_download;
    ph_list_files = debian_list_files;
    ph_get_file_from_package = debian_get_file_from_package;
  } in
  register_package_handler "debian" ph
