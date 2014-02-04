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

(* Poldek and RPM support. *)

open Unix
open Printf

open Supermin_package_handlers
open Supermin_utils
open Supermin_cmdline

(* Create a temporary directory for use by all the functions in this file. *)
let tmpdir = tmpdir ()

let poldek_rpm_detect () =
  file_exists "/etc/pld-release" &&
    Config.poldek <> "no" && Config.rpm <> "no"

let poldek_rpm_init () =
  if use_installed then
    eprintf "supermin: poldek_rpm driver assumes all packages are already installed when called with option --use-installed.\n%!"

let poldek_rpm_resolve_dependencies_and_download_no_installed names =
  (* Liberate this data from shell. *)
  let tmp_pkg_cache_dir = tmpdir // "pkg_cache_dir" in
  let tmp_root = tmpdir // "root" in
  let sh = sprintf "
%s
rpm --root=%s --initdb
install -d %s
poldek --root=%s --fetch=%s %s -u \
	$@
"
    (if verbose then "set -x" else "")
    tmp_root
    tmp_pkg_cache_dir
    tmp_root
    tmp_pkg_cache_dir
    (if verbose then "-v" else "-q")
    in
  run_shell sh names;

  (* http://rosettacode.org/wiki/Walk_a_directory/Recursively *)
  let walk_directory_tree dir pattern =
      let select str = Str.string_match (Str.regexp pattern) str 0 in
      let rec walk acc = function
      | [] -> (acc)
      | dir::tail ->
          let contents = Array.to_list (Sys.readdir dir) in
          let contents = List.rev_map (Filename.concat dir) contents in
          let dirs, files =
            List.fold_left (fun (dirs,files) f ->
                 match (stat f).st_kind with
                 | S_REG -> (dirs, f::files)  (* Regular file *)
                 | S_DIR -> (f::dirs, files)  (* Directory *)
                 | _ -> (dirs, files)
              ) ([],[]) contents
          in
          let matched = List.filter (select) files in
          walk (matched @ acc) (dirs @ tail)
      in
      walk [] [dir]
      in

  let pkgs = walk_directory_tree tmp_pkg_cache_dir  ".*\\.rpm" in

  (* Return list of package filenames. *)
  pkgs

let poldek_rpm_resolve_dependencies_and_download names mode =
  if mode = PkgNamesOnly then (
    eprintf "supermin: poldek-rpm: --names-only flag is not implemented\n";
    exit 1
  );

  if use_installed then
    (* TODO: try to understand from 9750c2e what should do on use_installed *)
    failwith "poldek_rpm driver doesn't support --use-installed"
  else
    poldek_rpm_resolve_dependencies_and_download_no_installed names

let rec poldek_rpm_list_files pkg =
  (* Run rpm -qlp with some extra magic. *)
  let cmd =
    sprintf "rpm -q --qf '[%%{FILENAMES} %%{FILEFLAGS:fflags} %%{FILEMODES} %%{FILESIZES}\\n]' %s %S"
      (if use_installed then "" else "-p")
      pkg in
  let lines = run_command_get_lines cmd in

  let files =
    filter_map (
      fun line ->
        match string_split " " line with
        | [filename; flags; mode; size] ->
            let test_flag = String.contains flags in
            let mode = int_of_string mode in
            let size = int_of_string size in
            if test_flag 'd' then None  (* ignore documentation *)
            else (
              (* Skip unreadable files when called as non-root *)
              if Unix.getuid() > 0 &&
                (try Unix.access filename [Unix.R_OK]; false with
                   Unix_error _ -> eprintf "supermin: EPERM %s\n%!" filename; true) then None
              else
              Some (filename, {
                      ft_dir = mode land 0o40000 <> 0;
                      ft_ghost = test_flag 'g'; ft_config = test_flag 'c';
                      ft_mode = mode; ft_size = size;
                    })
            )
        | _ ->
            eprintf "supermin: bad output from rpm command: '%s'" line;
            exit 1
    ) lines in

  (* I've never understood why the base packages like 'filesystem' don't
   * contain any /dev nodes at all.  This leaves every program that
   * bootstraps RPMs to create a varying set of device nodes themselves.
   * This collection was copied from mock/backend.py.
   *)
  let files =
    let b = Filename.basename pkg in
    if string_prefix "filesystem-" b then (
      let dirs = [ "/proc"; "/sys"; "/dev"; "/dev/pts"; "/dev/shm";
                   "/dev/mapper" ] in
      let dirs =
        List.map (fun name ->
                    name, { ft_dir = true; ft_ghost = false;
                            ft_config = false; ft_mode = 0o40755;
                            ft_size = 0 }) dirs in
      let devs = [ "/dev/null"; "/dev/full"; "/dev/zero"; "/dev/random";
                   "/dev/urandom"; "/dev/tty"; "/dev/console";
                   "/dev/ptmx"; "/dev/stdin"; "/dev/stdout"; "/dev/stderr" ] in
      (* No need to set the mode because these will go into hostfiles. *)
      let devs =
        List.map (fun name ->
                    name, { ft_dir = false; ft_ghost = false;
                            ft_config = false; ft_mode = 0o644;
                            ft_size = 0 }) devs in
      dirs @ devs @ files
    ) else files in

  files

let poldek_rpm_get_file_from_package pkg file =
  if use_installed then
    file
  else (
    debug "extracting %s from %s ..." file (Filename.basename pkg);

    let outfile = tmpdir // file in
    let cmd =
      sprintf "umask 0000; rpm2cpio %s | (cd %s && cpio --quiet -id .%s)"
        (Filename.quote pkg) (Filename.quote tmpdir) (Filename.quote file) in
    run_command cmd;
    outfile
    )

let () =
  let ph = {
    ph_detect = poldek_rpm_detect;
    ph_init = poldek_rpm_init;
    ph_resolve_dependencies_and_download =
      poldek_rpm_resolve_dependencies_and_download;
    ph_list_files = poldek_rpm_list_files;
    ph_get_file_from_package = poldek_rpm_get_file_from_package;
  } in
  register_package_handler "poldek" ph
