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
open Unix.LargeFile
open Printf

open Utils
open Package_handler

let pacman_detect () =
  Config.pacman <> "no" && Config.fakeroot <> "no" &&
    (Os_release.get_id () = "arch" ||
     ((stat "/etc/arch-release").st_kind = S_REG &&
      Config.pacman_g2 = "no")) (* not Frugalware with pacman-g2 *)

let settings = ref no_settings

let pacman_init s = settings := s

type pac_t = {
  name : string;
  epoch : int;
  version : string;
  release : string;
  arch : string;
}

(* Memo from package type to internal pac_t. *)
let pac_of_pkg, pkg_of_pac = get_memo_functions ()

(* Memo of pacman_package_of_string. *)
let pach = Hashtbl.create 13

let pacman_package_of_string str =
  (* Parse a package name into the fields like name and version. *)
  let parse_pac str =
    let cmd = sprintf "%s -Qi %s" Config.pacman (quote str) in
    if !settings.debug >= 2 then printf "%s" cmd;
    let lines = run_command_get_lines cmd in

    let name = ref "" and evr = ref "" and arch = ref "" in
    List.iter (
      fun line ->
        let get_value r =
          let len = String.length line in
          let i = String.index line ':' in
          r := String.sub line (i+2) (len-(i+2))
        in
        if string_prefix "Name " line then get_value name
        else if string_prefix "Version " line then get_value evr
        else if string_prefix "Architecture " line then get_value arch
    ) lines;

    let name = !name and evr = !evr and arch = !arch in
    if name = "" || evr = "" || arch = "" then
      error "pacman: Name/Version/Architecture field missing in output of %s" cmd;

    (* Parse epoch:version-release field. *)
    let epoch, version, release =
      try
        let epoch, vr =
          try
            let i = String.index evr ':' in
            int_of_string (String.sub evr 0 i),
            String.sub evr (i+1) (String.length evr - (i+1))
          with Not_found -> 0, evr in
        let version, release =
          match string_split "-" vr with
          | [ v; r ] -> v, r
          | _ -> assert false in
        epoch, version, release
      with
        Failure "int_of_string" ->
          failwith ("failed to parse epoch:version-release field " ^ evr) in

    { name = name;
      epoch = epoch;
      version = version;
      release = release;
      arch = arch }

  (* Check if a package is installed. *)
  and check_pac_installed name =
    let cmd = sprintf "%s -Qq %s >/dev/null 2>&1" Config.pacman (quote name) in
    if !settings.debug >= 2 then printf "%s" cmd;
    0 = Sys.command cmd
  in

  try
    Hashtbl.find pach str
  with
    Not_found ->
      let r =
        if check_pac_installed str then (
          let pac = parse_pac str in
          Some (pkg_of_pac pac)
        )
        else None in
      Hashtbl.add pach str r;
      r

let pacman_package_to_string pkg =
  let pac = pac_of_pkg pkg in
  if pac.epoch = 0 then
    sprintf "%s-%s-%s.%s" pac.name pac.version pac.release pac.arch
  else
    sprintf "%s-%d:%s-%s.%s"
      pac.name pac.epoch pac.version pac.release pac.arch

let pacman_package_name pkg =
  let pac = pac_of_pkg pkg in
  pac.name

let pacman_get_package_database_mtime () =
  (lstat "/var/lib/pacman/sync/core.db" (* XXX? *) ).st_mtime

let pacman_get_all_requires pkgs =
  let cmd = sprintf "\
    for p in %s; do %s -u $p; done | awk '{print $1}' | sort -u
  " (quoted_list (List.map pacman_package_name (PackageSet.elements pkgs)))
    Config.pactree in
  if !settings.debug >= 2 then printf "%s" cmd;
  let lines = run_command_get_lines cmd in
  let lines = filter_map pacman_package_of_string lines in
  PackageSet.union pkgs (package_set_of_list lines)

let pacman_get_all_files pkgs =
  let cmd =
    sprintf "%s -Ql %s | awk '{print $2}'"
      Config.pacman
      (quoted_list (List.map pacman_package_name (PackageSet.elements pkgs))) in
  if !settings.debug >= 2 then printf "%s" cmd;
  let lines = run_command_get_lines cmd in
  List.map (
    fun path ->
      (* Remove trailing / from directory names. *)
      let path =
        let len = String.length path in
        if len >= 2 && path.[len-1] = '/' then
          String.sub path 0 (len-1)
        else
          path in
      let config =
	try string_prefix "/etc/" path && (lstat path).st_kind = S_REG
	with Unix_error _ -> false in
      { ft_path = path; ft_source_path = path; ft_config = config }
  ) lines

let pacman_download_all_packages pkgs dir =
  let tdir = !settings.tmpdir // string_random8 () in
  mkdir tdir 0o755;

  let names = List.map pacman_package_name (PackageSet.elements pkgs) in

  (* Because we reuse the same temporary download directory (tdir), this
   * only downloads each package once, even though each call to pacman will
   * download dependent packages as well.
   *
   * CacheDir directives must be filtered out to force pacman downloads.
   *)
  let cmd = sprintf "\
    set -e
    umask 0000
    cd %s
    mkdir -p var/lib/pacman
    pacman-conf | grep -v CacheDir > tmp.conf
    %s %s%s -Syw --noconfirm --cachedir=$(pwd) --root=$(pwd) %s
  "
    (quote tdir)
    Config.fakeroot Config.pacman
    (match !settings.packager_config with
     | None -> " --config tmp.conf --dbpath var/lib/pacman"
     | Some filename -> " --config " ^ (quote filename))
    (quoted_list names) in
  if !settings.debug >= 2 then printf "%s" cmd;
  if Sys.command cmd <> 0 then (
    (* The package may not be in the main repos, check the AUR. *)
    List.iter (
      fun name ->
        let cmd = sprintf "\
          set -e
          umask 0000
          cd %s
          wget %s
          tar xf %s
          cd %s
          %s
          mv %s-*.pkg.tar.xz %s
       "
          (quote tdir)
          (quote ("https://aur.archlinux.org/packages/" ^
	    (String.sub name 0 2) ^
	    "/" ^ name ^ "/" ^ name ^ ".tar.gz"))
          (quote (name ^ ".tar.gz"))
          (quote name) (* cd *)
          Config.makepkg
          (quote name) (quote tdir) (* mv *) in
        if !settings.debug >= 2 then printf "%s" cmd;
        run_command cmd
    ) names;
  );

  (* Unpack the downloaded packages. *)
  let cmd =
    sprintf "
      umask 0000
      for f in %s/*.pkg.tar.*; do
        [[ $f == *.sig ]] && continue
        tar -xf \"$f\" -C %s
      done
    "
      (quote tdir) (quote dir) in
  if !settings.debug >= 2 then printf "%s" cmd;
  run_command cmd

let () =
  let ph = {
    ph_detect = pacman_detect;
    ph_init = pacman_init;
    ph_fini = (fun () -> ());
    ph_package_of_string = pacman_package_of_string;
    ph_package_to_string = pacman_package_to_string;
    ph_package_name = pacman_package_name;
    ph_get_package_database_mtime = pacman_get_package_database_mtime;
    ph_get_requires = PHGetAllRequires pacman_get_all_requires;
    ph_get_files = PHGetAllFiles pacman_get_all_files;
    ph_download_package = PHDownloadAllPackages pacman_download_all_packages;
  } in
  register_package_handler "arch" "pacman" ph
