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
open Package_handler

let dpkg_detect () =
  Config.dpkg <> "no" &&
    Config.dpkg_deb <> "no" &&
    Config.dpkg_query <> "no" &&
    Config.dpkg_divert <> "no" &&
    Config.apt_get <> "no" &&
    try (stat "/etc/debian_version").st_kind = S_REG with Unix_error _ -> false

let dpkg_primary_arch = ref ""
let settings = ref no_settings

let dpkg_init s =
  settings := s;

  let cmd = sprintf "%s --print-architecture" Config.dpkg in
  let lines = run_command_get_lines cmd in
  match lines with
  | [] -> error "dpkg: expecting %s to return some output" cmd
  | arch :: _ -> dpkg_primary_arch := arch

type dpkg_t = {
  name : string;
  version : string;
  arch : string;
}

(* Memo from package type to internal dpkg_t. *)
let dpkg_of_pkg, pkg_of_dpkg = get_memo_functions ()

let dpkg_packages = Hashtbl.create 13
let dpkg_package_of_string str =
  if Hashtbl.length dpkg_packages == 0 then (
    let cmd =
      sprintf "%s --show --showformat='${Package} ${Version} ${Architecture} ${Status}\\n'"
        Config.dpkg_query in
    let lines = run_command_get_lines cmd in
    List.iter (
      fun line ->
        match string_split " " line with
        | [ name; version; arch; _; _; "installed" ] ->
          let dpkg = { name = name; version = version; arch = arch } in
          Hashtbl.add dpkg_packages name dpkg
        | _ -> ();
    ) lines
  );
  let candidates = Hashtbl.find_all dpkg_packages str in
  (* On multiarch setups, only consider the primary architecture *)
  try
    let pkg = List.find (
      fun cand ->
        cand.arch = !dpkg_primary_arch || cand.arch = "all"
    ) candidates in
    Some (pkg_of_dpkg pkg)
  with
    Not_found -> None

let dpkg_package_to_string pkg =
  let dpkg = dpkg_of_pkg pkg in
  sprintf "%s_%s_%s" dpkg.name dpkg.version dpkg.arch

let dpkg_package_name pkg =
  let dpkg = dpkg_of_pkg pkg in
  dpkg.name

let dpkg_package_name_arch pkg =
  let dpkg = dpkg_of_pkg pkg in
  sprintf "%s:%s" dpkg.name dpkg.arch

let dpkg_get_package_database_mtime () =
  (lstat "/var/lib/dpkg/status").st_mtime

let dpkg_get_all_requires pkgs =
  let dpkg_requires = Hashtbl.create 13 in
  (* Prepare dpkg_requires hashtbl with depends, pre-depends from all
     packages. Strip version information and discard alternative
     dependencies *)
  let cmd = sprintf "\
      %s --show --showformat='${Package} ${Depends} ${Pre-Depends}\n' | \
      sed -e 's/ *([^)]*) */ /g' \
          -e 's/ *, */ /g' \
          -e 's/ *| *[^ ]* */ /g'"
    Config.dpkg_query in
  let lines = run_command_get_lines cmd in
  List.iter (
    fun line ->
      match string_split " " line with
      | [] -> ()
      | pkgname :: [] -> ()
      | pkgname :: deps -> Hashtbl.add dpkg_requires pkgname deps
  ) lines;

  let get pkgs =
    let pkgnames = List.map dpkg_package_name (PackageSet.elements pkgs) in
    let deps = List.map (Hashtbl.find_all dpkg_requires) pkgnames in
    let deps = List.flatten (List.flatten deps) in
    let deps = filter_map dpkg_package_of_string deps in
    PackageSet.union pkgs (package_set_of_list deps)
  in
  (* The command above only gets one level of dependencies.  We need
   * to keep iterating until we reach a fixpoint.
   *)
  let rec loop pkgs =
    let pkgs' = get pkgs in
    if PackageSet.equal pkgs pkgs' then pkgs
    else loop pkgs'
  in
  loop pkgs

let dpkg_diversions = Hashtbl.create 13
let dpkg_get_all_files pkgs =
  if Hashtbl.length dpkg_diversions = 0 then (
    let cmd = sprintf "%s --list" Config.dpkg_divert in
    let lines = run_command_get_lines cmd in
    List.iter (
      fun line ->
        let items = string_split " " line in
        match items with
        | ["diversion"; "of"; path; "to"; real_path; "by"; pkg] ->
          Hashtbl.add dpkg_diversions path real_path
        | _ -> ()
    ) lines
  );
  let cmd =
    sprintf "%s --listfiles %s | grep '^/' | grep -v '^/.$' | sort -u"
      Config.dpkg_query
      (quoted_list (List.map dpkg_package_name_arch
		      (PackageSet.elements pkgs))) in
  let lines = run_command_get_lines cmd in
  List.map (
    fun path ->
      let config =
	try string_prefix "/etc/" path && (lstat path).st_kind = S_REG
	with Unix_error _ -> false in
      let source_path =
        try Hashtbl.find dpkg_diversions path
        with Not_found -> path in
      { ft_path = path; ft_source_path = source_path; ft_config = config }
  ) lines

let dpkg_download_all_packages pkgs dir =
  let tdir = !settings.tmpdir // string_random8 () in
  mkdir tdir 0o755;

  let dpkgs = List.map dpkg_package_name (PackageSet.elements pkgs) in

  let cmd =
    sprintf "cd %s && %s %s download %s"
      (quote tdir)
      Config.apt_get
      (if !settings.debug >= 1 then "" else " --quiet --quiet")
      (quoted_list dpkgs) in
  run_command cmd;

  (* Unpack each downloaded package. *)
  let cmd =
    sprintf "
umask 0000
for f in %s/*.deb; do
  %s --fsys-tarfile \"$f\" | (cd %s && tar xf -)
done"
      (quote tdir) Config.dpkg_deb (quote dir) in
  run_command cmd

let () =
  let ph = {
    ph_detect = dpkg_detect;
    ph_init = dpkg_init;
    ph_fini = (fun () -> ());
    ph_package_of_string = dpkg_package_of_string;
    ph_package_to_string = dpkg_package_to_string;
    ph_package_name = dpkg_package_name;
    ph_get_package_database_mtime = dpkg_get_package_database_mtime;
    ph_get_requires = PHGetAllRequires dpkg_get_all_requires;
    ph_get_files = PHGetAllFiles dpkg_get_all_files;
    ph_download_package = PHDownloadAllPackages dpkg_download_all_packages;
  } in
  register_package_handler "debian" "dpkg" ph
