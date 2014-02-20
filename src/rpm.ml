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

let rpm_detect () =
  Config.rpm <> "no" &&
    Config.yumdownloader <> "no" &&
    (file_exists "/etc/redhat-release" ||
       file_exists "/etc/fedora-release")

let settings = ref no_settings

let rpm_init s = settings := s

type rpm_t = {
  name : string;
  epoch : int32;
  version : string;
  release : string;
  arch : string;
}

(* Memo from package type to internal rpm_t. *)
let rpm_of_pkg, pkg_of_rpm = get_memo_functions ()

(* Memo of rpm_package_of_string. *)
let rpmh = Hashtbl.create 13

let rpm_package_of_string str =
  (* Parse an RPM name into the fields like name and version.  Since
   * the package is installed (see check below), it's easier to use RPM
   * itself to do this parsing rather than haphazardly parsing it
   * ourselves.  *)
  let parse_rpm str =
    let cmd =
      sprintf "rpm -q --qf '%%{name} %%{epoch} %%{version} %%{release} %%{arch}\\n' %s"
        (quote str) in
    let lines = run_command_get_lines cmd in
    let lines = List.map (string_split " ") lines in
    let rpms = filter_map (
      function
      | [ name; ("0"|"(none)"); version; release; arch ] ->
        Some { name = name;
               epoch = 0_l;
               version = version; release = release; arch = arch }
      | [ name; epoch; version; release; arch ] ->
        Some { name = name;
               epoch = Int32.of_string epoch;
               version = version; release = release; arch = arch }
      | xs ->
        (* grrr, RPM doesn't send errors to stderr *)
        None
    ) lines in

    if rpms = [] then (
      eprintf "supermin: no output from rpm command could be parsed when searching for '%s'\nThe command was:\n  %s\n"
        str cmd;
      exit 1
    );

    (* RPM will return multiple hits when either multiple versions or
     * multiple arches are installed at the same time.  We are only
     * interested in the highest version with the best
     * architecture.
     *)
    let cmp { version = v1; arch = a1 } { version = v2; arch = a2 } =
      let i = compare_version v2 v1 in
      if i <> 0 then i
      else compare_architecture a2 a1
    in
    let rpms = List.sort cmp rpms in
    List.hd rpms

  (* Check if an RPM is installed. *)
  and check_rpm_installed name =
    let cmd = sprintf "rpm -q %s >/dev/null" (quote name) in
    0 = Sys.command cmd
  in

  try
    Hashtbl.find rpmh str
  with
    Not_found ->
      let r =
        if check_rpm_installed str then (
          let rpm = parse_rpm str in
          Some (pkg_of_rpm rpm)
        )
        else None in
      Hashtbl.add rpmh str r;
      r

let rpm_package_to_string pkg =
  let rpm = rpm_of_pkg pkg in
  if rpm.epoch = 0_l then
    sprintf "%s-%s-%s.%s" rpm.name rpm.version rpm.release rpm.arch
  else
    sprintf "%s-%ld:%s-%s.%s"
      rpm.name rpm.epoch rpm.version rpm.release rpm.arch

let rpm_package_name pkg =
  let rpm = rpm_of_pkg pkg in
  rpm.name

let rpm_get_all_requires pkgs =
  let get pkgs =
    let cmd = sprintf "\
        rpm -qR %s |
        awk '{print $1}' |
        xargs rpm -q --qf '%%{name}\\n' --whatprovides |
        grep -v 'no package provides' |
        sort -u"
      (quoted_list (List.map rpm_package_to_string
                      (PackageSet.elements pkgs))) in
    let lines = run_command_get_lines cmd in
    let lines = filter_map rpm_package_of_string lines in
    PackageSet.union pkgs (package_set_of_list lines)
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

let rpm_get_requires pkg = rpm_get_all_requires (PackageSet.singleton pkg)

let rpm_get_all_files pkgs =
  let cmd = sprintf "\
      rpm -q --qf '[%%{FILENAMES} %%{FILEFLAGS:fflags}\\n]' %s |
      grep '^/' |
      sort -u"
    (quoted_list (List.map rpm_package_to_string (PackageSet.elements pkgs))) in
  let lines = run_command_get_lines cmd in
  let lines = List.map (string_split " ") lines in
  List.map (
    function
    | [ path; flags ] ->
      let config = String.contains flags 'c' in
      { ft_path = path; ft_config = config }
    | _ -> assert false
  ) lines

let rpm_get_files pkg = rpm_get_all_files (PackageSet.singleton pkg)

let rpm_download_all_packages pkgs dir =
  let tdir = !settings.tmpdir // string_random8 () in

  (* It's quite complex to get yumdownloader to download specific
   * RPMs.  If we use the full NVR, then it will refuse if an installed
   * RPM is older than whatever is currently in the repo.  If we use
   * just name, it will download all architectures (even with
   * --archlist).
   * 
   * Use name.arch so it can download any version but only the specific
   * architecture.
   *)
  let rpms = List.map rpm_of_pkg (PackageSet.elements pkgs) in
  let rpms = List.map (
    fun { name = name; arch = arch } ->
      sprintf "%s.%s" name arch
  ) rpms in

  let cmd =
    sprintf "%s%s%s --destdir %s %s"
      Config.yumdownloader
      (if !settings.debug >= 1 then "" else " --quiet")
      (match !settings.packager_config with
      | None -> ""
      | Some filename -> sprintf " -c %s" (quote filename))
      (quote tdir)
      (quoted_list rpms) in
  run_command cmd;

  (* Unpack each downloaded package.
   * 
   * yumdownloader can't necessarily download the specific file that we
   * requested, we might get a different (eg later) version.
   *)
  let cmd =
    sprintf "
umask 0000
for f in %s/*.rpm; do
  rpm2cpio \"$f\" | (cd %s && cpio --quiet -id)
done"
      (quote tdir) (quote dir) in
  run_command cmd

let rpm_download_package pkg dir =
  rpm_download_all_packages (PackageSet.singleton pkg) dir

let rpm_get_package_database_mtime () =
  (lstat "/var/lib/rpm/Packages").st_mtime

let () =
  let ph = {
    ph_detect = rpm_detect;
    ph_init = rpm_init;
    ph_package_of_string = rpm_package_of_string;
    ph_package_to_string = rpm_package_to_string;
    ph_package_name = rpm_package_name;
    ph_get_requires = rpm_get_requires;
    ph_get_all_requires = rpm_get_all_requires;
    ph_get_files = rpm_get_files;
    ph_get_all_files = rpm_get_all_files;
    ph_download_package = rpm_download_package;
    ph_download_all_packages = rpm_download_all_packages;
    ph_get_package_database_mtime = rpm_get_package_database_mtime;
  } in
  register_package_handler "rpm" ph
