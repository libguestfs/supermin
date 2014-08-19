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

let fedora_detect () =
  Config.rpm <> "no" && Config.rpm2cpio <> "no" &&
    Config.yumdownloader <> "no" &&
    try
      (stat "/etc/redhat-release").st_kind = S_REG ||
      (stat "/etc/fedora-release").st_kind = S_REG
    with Unix_error _ -> false

let opensuse_detect () =
  Config.rpm <> "no" && Config.rpm2cpio <> "no" &&
    Config.zypper <> "no" &&
    try (stat "/etc/SuSE-release").st_kind = S_REG with Unix_error _ -> false

let mageia_detect () =
  Config.rpm <> "no" && Config.rpm2cpio <> "no" &&
    Config.urpmi <> "no" &&
    Config.fakeroot <> "no" &&
    try (stat "/etc/mageia-release").st_kind = S_REG with Unix_error _ -> false

let settings = ref no_settings
let rpm_major, rpm_minor = ref 0, ref 0
let zypper_major, zypper_minor, zypper_patch = ref 0, ref 0, ref 0

let rec rpm_init s =
  settings := s;

  (* Get RPM version. We have to adjust some RPM commands based on
   * the version.
   *)
  let cmd = sprintf "%s --version | awk '{print $3}'" Config.rpm in
  let lines = run_command_get_lines cmd in
  let major, minor =
    match lines with
    | [] ->
      eprintf "supermin: rpm --version command had no output\n";
      exit 1
    | line :: _ ->
      let line = string_split "." line in
      match line with
      | [] ->
        eprintf "supermin: unable to parse empty output of rpm --version\n";
        exit 1
      | [x] ->
        eprintf "supermin: unable to parse output of rpm --version: %s\n" x;
        exit 1
      | major :: minor :: _ ->
        try int_of_string major, int_of_string minor
        with Failure "int_of_string" ->
          eprintf "supermin: unable to parse output of rpm --version: non-numeric\n";
          exit 1 in
  rpm_major := major;
  rpm_minor := minor;
  if !settings.debug >= 1 then
    printf "supermin: rpm: detected RPM version %d.%d\n" major minor

and opensuse_init s =
  rpm_init s;

  (* Get zypper version. We can use better zypper commands with more
   * recent versions.
   *)
  let cmd = sprintf "%s --version | awk '{print $2}'" Config.zypper in
  let lines = run_command_get_lines cmd in
  let major, minor, patch =
    match lines with
    | [] ->
      eprintf "supermin: zypper --version command had no output\n";
      exit 1
    | line :: _ ->
      let line = string_split "." line in
      match line with
      | [] ->
        eprintf "supermin: unable to parse empty output of zypper --version\n";
        exit 1
      | [x] ->
        eprintf "supermin: unable to parse output of zypper --version: %s\n" x;
        exit 1
      | major :: minor :: [] ->
        (try int_of_string major, int_of_string minor, 0
        with Failure "int_of_string" ->
          eprintf "supermin: unable to parse output of zypper --version: non-numeric\n";
          exit 1)
      | major :: minor :: patch :: _ ->
        (try int_of_string major, int_of_string minor, int_of_string patch
        with Failure "int_of_string" ->
          eprintf "supermin: unable to parse output of zypper --version: non-numeric\n";
          exit 1) in
  zypper_major := major;
  zypper_minor := minor;
  zypper_patch := patch;
  if !settings.debug >= 1 then
    printf "supermin: rpm: detected zypper version %d.%d.%d\n" major minor patch

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
      sprintf "%s -q --qf '%%{name} %%{epoch} %%{version} %%{release} %%{arch}\\n' %s"
        Config.rpm
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
    let cmd = sprintf "%s -q %s >/dev/null" Config.rpm (quote name) in
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
  (* In RPM < 4.11 query commands that use the epoch number in the
   * package name did not work.
   *
   * For example:
   * RHEL 6 (rpm 4.8.0):
   *   $ rpm -q tar-2:1.23-11.el6.x86_64
   *   package tar-2:1.23-11.el6.x86_64 is not installed
   * Fedora 20 (rpm 4.11.2):
   *   $ rpm -q tar-2:1.26-30.fc20.x86_64
   *   tar-1.26-30.fc20.x86_64
   *
   *)
  let is_rpm_lt_4_11 =
    !rpm_major < 4 || (!rpm_major = 4 && !rpm_minor < 11) in

  let rpm = rpm_of_pkg pkg in
  if is_rpm_lt_4_11 || rpm.epoch = 0_l then
    sprintf "%s-%s-%s.%s" rpm.name rpm.version rpm.release rpm.arch
  else
    sprintf "%s-%ld:%s-%s.%s"
      rpm.name rpm.epoch rpm.version rpm.release rpm.arch

let rpm_package_name pkg =
  let rpm = rpm_of_pkg pkg in
  rpm.name

let rpm_get_package_database_mtime () =
  (lstat "/var/lib/rpm/Packages").st_mtime

let rpm_get_all_requires pkgs =
  let get pkgs =
    let cmd = sprintf "\
        %s -qR %s |
        awk '{print $1}' |
        xargs rpm -q --qf '%%{name}\\n' --whatprovides |
        grep -v 'no package provides' |
        sort -u"
      Config.rpm
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

let rpm_get_all_files pkgs =
  let cmd = sprintf "\
      %s -q --qf '[%%{FILENAMES}\\t%%{FILEFLAGS:fflags}\\n]' %s |
      grep '^/' |
      sort -u"
    Config.rpm
    (quoted_list (List.map rpm_package_to_string (PackageSet.elements pkgs))) in
  let lines = run_command_get_lines cmd in
  let lines = List.map (string_split "\t") lines in
  List.map (
    function
    | [ path; flags ] ->
      let config = String.contains flags 'c' in
      { ft_path = path; ft_source_path = path; ft_config = config }
    | _ -> assert false
  ) lines

let rec fedora_download_all_packages pkgs dir =
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

  rpm_unpack tdir dir

and opensuse_download_all_packages pkgs dir =
  let tdir = !settings.tmpdir // string_random8 () in

  let rpms = List.map rpm_of_pkg (PackageSet.elements pkgs) in
  let rpms = List.map (
    fun { name = name; arch = arch } ->
      sprintf "%s.%s" name arch
  ) rpms in

  let is_zypper_1_9_14 =
    !zypper_major > 1
    || (!zypper_major = 1 && !zypper_minor > 9)
    || (!zypper_major = 1 && !zypper_minor = 9 && !zypper_patch >= 14) in

  let cmd =
    if is_zypper_1_9_14 then
      sprintf "
        %s%s \\
          --reposd-dir /etc/zypp/repos.d \\
          --cache-dir %s \\
          --pkg-cache-dir %s \\
          --gpg-auto-import-keys --no-gpg-checks --non-interactive \\
          download \\
          %s"
        Config.zypper
        (if !settings.debug >= 1 then " --verbose --verbose" else " --quiet")
        (quote tdir)
        (quote tdir)
        (quoted_list rpms)
    else
      (* This isn't quite right because zypper will resolve the dependencies
       * of the listed packages against the public repos and download all the
       * dependencies too.  We only really want it to download the named
       * packages. XXX
       *)
      sprintf "
        %s%s \\
          --root %s \\
          --reposd-dir /etc/zypp/repos.d \\
          --cache-dir %s \\
          --pkg-cache-dir %s \\
          --gpg-auto-import-keys --no-gpg-checks --non-interactive \\
          install \\
          --auto-agree-with-licenses --download-only --no-recommends \\
          %s"
        Config.zypper
        (if !settings.debug >= 1 then " --verbose --verbose" else " --quiet")
        (quote tdir)
        (quote tdir)
        (quote tdir)
        (quoted_list rpms) in
  run_command cmd;

  rpm_unpack tdir dir

and mageia_download_all_packages pkgs dir =
  let tdir = !settings.tmpdir // string_random8 () in

  let rpms = List.map rpm_package_name (PackageSet.elements pkgs) in

  let cmd =
    sprintf "
      %s %s%s \\
        --download-all %s \\
        --replacepkgs \\
        --no-install \\
        %s"
      Config.fakeroot
      Config.urpmi
      (if !settings.debug >= 1 then " --verbose" else " --quiet")
      (quote tdir)
      (quoted_list rpms) in
  run_command cmd;

  rpm_unpack tdir dir

and rpm_unpack tdir dir =
  (* Unpack each downloaded package.
   * 
   * yumdownloader can't necessarily download the specific file that we
   * requested, we might get a different (eg later) version.
   *)
  let cmd =
    sprintf "
umask 0000
for f in `find %s -name '*.rpm'`; do
  %s \"$f\" | (cd %s && %s --quiet -id)
done"
      (quote tdir) Config.rpm2cpio (quote dir) Config.cpio in
  run_command cmd

(* We register package handlers for each RPM distro variant. *)
let () =
  let fedora = {
    ph_detect = fedora_detect;
    ph_init = rpm_init;
    ph_package_of_string = rpm_package_of_string;
    ph_package_to_string = rpm_package_to_string;
    ph_package_name = rpm_package_name;
    ph_get_package_database_mtime = rpm_get_package_database_mtime;
    ph_get_requires = PHGetAllRequires rpm_get_all_requires;
    ph_get_files = PHGetAllFiles rpm_get_all_files;
    ph_download_package = PHDownloadAllPackages fedora_download_all_packages;
  } in
  register_package_handler "fedora" "rpm" fedora;
  let opensuse = {
    fedora with
    ph_detect = opensuse_detect;
    ph_init = opensuse_init;
    ph_download_package = PHDownloadAllPackages opensuse_download_all_packages;
  } in
  register_package_handler "opensuse" "rpm" opensuse;
  let mageia = {
    fedora with
    ph_detect = mageia_detect;
    ph_download_package = PHDownloadAllPackages mageia_download_all_packages;
  } in
  register_package_handler "mageia" "rpm" mageia
