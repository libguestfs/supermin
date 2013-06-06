(* supermin 4
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

(* Zypper and RPM support. *)

(*
 * Theory of operation:
 * called as root:
 *  - without --use-installed:
 *    ->ph_resolve_dependencies_and_download() returns a list of filenames
 *    Need to download all packages into an empty --root directory so that
 *    zypper places all dependencies into --pkg-cache-dir
 *  - with --use-installed:
 *    ->ph_resolve_dependencies_and_download() returns a list of package names
 *    Need to work with an empty --root directory so that zypper can list
 *    all dependencies of "names". This mode assumes that all required packages
 *    are installed and the system is consistent. Downloading just the missing
 *    packages is not implemented.
 * called as non-root:
 *    (Due to the usage of --root zypper does not require root permissions.)
 *  - without --use-installed:
 *    Same as above.
 *  - with --use-installed:
 *    Same as above.
 *
 * The usage of --packager-config is tricky: If --root is used zypper assumes
 * that every config file is below <rootdir>. So the config has to be parsed
 * and relevant files/dirs should be copied into <rootdir> so that zypper can
 * use the specified config.
 *)
open Unix
open Printf
open Inifiles

open Supermin_package_handlers
open Supermin_utils
open Supermin_cmdline


(* Create a temporary directory for use by all the functions in this file. *)
let tmpdir = tmpdir ()

let get_repos_dir () =
  let zypper_default = "/etc/zypp/repos.d" in
  let parse_repos_dir path =
    let cfg = new inifile path in
    let dir = (try cfg#getval "main" "reposdir" with _ -> zypper_default) in
    dir
  in
  let dir = (match packager_config with None -> zypper_default |
      Some filename -> (try parse_repos_dir filename with _ -> zypper_default) ) in
  dir

let repos_dir = get_repos_dir ()

let zypp_rpm_detect () =
  (file_exists "/etc/SuSE-release") &&
    Config.zypper <> "no" && Config.rpm <> "no"

let zypp_rpm_init () =
  if use_installed then
    eprintf "supermin: zypp_rpm driver assumes all packages are already installed when called with option --use-installed.\n%!"

let zypp_rpm_resolve_dependencies_and_download_no_installed names =
  (* Liberate this data from shell. *)
  let tmp_pkg_cache_dir = tmpdir // "pkg_cache_dir" in
  let tmp_root = tmpdir // "root" in
  let sh = sprintf "
%s
unset LANG ${!LC_*}
tmpdir=%S
cache_dir=\"${tmpdir}/cache-dir\"
pkg_cache_dir=%S
time zypper \
	%s \
	%s \
	--root %S --reposd-dir %S \
	--cache-dir \"${cache_dir}\" \
	--pkg-cache-dir \"${pkg_cache_dir}\" \
	--gpg-auto-import-keys \
	--no-gpg-checks \
	--non-interactive \
	install \
	--auto-agree-with-licenses \
	--download-only \
	$@
"
    (if verbose then "set -x" else "")
    tmpdir
    tmp_pkg_cache_dir
    (if verbose then "--verbose --verbose" else "--quiet")
    (match packager_config with None -> ""
     | Some filename -> sprintf "--config %s" filename)
    tmp_root
    repos_dir
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

let zypp_rpm_resolve_dependencies_and_download_use_installed names =
  let cmd = sprintf "
%s
unset LANG ${!LC_*}
zypper \
	%s \
	%s \
	--root %S --reposd-dir %S \
	--cache-dir %S \
	--gpg-auto-import-keys \
	--no-gpg-checks \
	--non-interactive \
	--xml \
	install \
	--auto-agree-with-licenses \
	--dry-run \
	%s | \
	xml sel -t \
	-m \"stream/install-summary/to-install/solvable[@type='package']\" \
	-c \"string(@name)\" -n
"
    (if verbose then "set -x" else "")
    (if verbose then "--verbose --verbose" else "--quiet")
    (match packager_config with None -> ""
     | Some filename -> sprintf "--config %s" filename)
    tmpdir repos_dir tmpdir (String.concat " " (List.map Filename.quote names)) in
  let pkg_names = run_command_get_lines cmd in

  (* Return list of package names, remove empty lines. *)
  List.filter (fun s -> s <> "") pkg_names

let zypp_rpm_resolve_dependencies_and_download names mode =
  if mode = PkgNamesOnly then (
    eprintf "supermin: zypp-rpm: --names-only flag is not implemented\n";
    exit 1
  );

  if use_installed then
    zypp_rpm_resolve_dependencies_and_download_use_installed names
  else
    zypp_rpm_resolve_dependencies_and_download_no_installed names

let rec zypp_rpm_list_files pkg =
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

let zypp_rpm_get_file_from_package pkg file =
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
    ph_detect = zypp_rpm_detect;
    ph_init = zypp_rpm_init;
    ph_resolve_dependencies_and_download =
      zypp_rpm_resolve_dependencies_and_download;
    ph_list_files = zypp_rpm_list_files;
    ph_get_file_from_package = zypp_rpm_get_file_from_package;
  } in
  register_package_handler "zypp-rpm" ph
