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

(* ArchLinux support. *)

open Unix
open Printf

open Supermin_package_handlers
open Supermin_utils
open Supermin_cmdline

(* Create a temporary directory for use by all the functions in this file. *)
let tmpdir = tmpdir ()

let pacman_detect () =
  file_exists "/etc/arch-release" &&
    Config.pacman <> "no"

let pacman_init () =
  if use_installed then
    failwith "pacman driver doesn't support --use-installed"

let pacman_resolve_dependencies_and_download names mode =
  if mode = PkgNamesOnly then (
    eprintf "supermin: pacman: --names-only flag is not implemented\n";
    exit 1
  );

  let cmd =
    sprintf "(for p in %s; do pactree -u $p; done) | awk '{print $1}' | sort -u"
      (String.concat " " (List.map Filename.quote names)) in
  let pkgs = run_command_get_lines cmd in

  (* Exclude packages matching [--exclude] regexps on the command line. *)
  let pkgs =
    List.filter (
      fun name ->
        not (List.exists (fun re -> Str.string_match re name 0) excludes)
    ) pkgs in

  (* Download the packages. I could use wget `pacman -Sp`, but this
   * narrows the pacman -Sy window
   *)

  List.iter (
    fun pkg ->
      let cmd =
        sprintf "umask 0000; cd %s && mkdir -p var/lib/pacman && fakeroot pacman%s -Syw --noconfirm --cachedir=$(pwd) --root=$(pwd) %s"
        (Filename.quote tmpdir)
	(match packager_config with
         | None -> ""
         | Some filename -> " --config " ^ filename)
        pkg in
      if Sys.command cmd <> 0 then (
          (* The package is not in the main repos, check the aur *)
          let cmd =
            sprintf "umask 0000; cd %s && wget https://aur.archlinux.org/packages/%s/%s/%s.tar.gz && tar xf %s.tar.gz && cd %s && makepkg && mv %s-*.pkg.tar.xz %s"
            (Filename.quote tmpdir)
            (String.sub pkg 0 2)
            pkg
            pkg
            pkg
            pkg
            pkg
            (Filename.quote tmpdir) in
          run_command cmd;
        )
  ) pkgs;

  List.sort compare pkgs

let pacman_list_files pkg =
  debug "unpacking %s ..." pkg;

  (* We actually need to extract the file in order to get the
   * information about modes etc.
   *)
  let pkgdir = tmpdir // pkg ^ ".d" in
  mkdir pkgdir 0o755;
  let cmd =
    sprintf "ls -1 %s/%s-*.pkg.* | awk '/\\/%s-[^/-]*-[^/-]*-[^/-]*$/ { print $0 }'"
      tmpdir pkg pkg in
  let pkgfile = List.hd (run_command_get_lines cmd) in
    let cmd = sprintf "umask 0000; fakeroot tar -xf %s -C %s"
              (Filename.quote pkgfile) (Filename.quote pkgdir) in
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
      let config = statbuf.st_kind = S_REG && string_prefix "/etc/" path in

      let mode = statbuf.st_perm in

      (path, { ft_dir = is_dir; ft_config = config; ft_mode = mode;
	       ft_ghost = false; ft_size = statbuf.st_size })
  ) lines in

  files

(* Easy because we already unpacked the archive above. *)
let pacman_get_file_from_package pkg file =
  tmpdir // pkg ^ ".d" // file

let () =
  let ph = {
    ph_detect = pacman_detect;
    ph_init = pacman_init;
    ph_resolve_dependencies_and_download =
      pacman_resolve_dependencies_and_download;
    ph_list_files = pacman_list_files;
    ph_get_file_from_package = pacman_get_file_from_package;
  } in
  register_package_handler "pacman" ph
