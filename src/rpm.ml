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
open Librpm

module StringSet = Set.Make (String)

let stringset_of_list pkgs =
  List.fold_left (fun set elem -> StringSet.add elem set) StringSet.empty pkgs

let fedora_detect () =
  Config.rpm <> "no" && Config.rpm2cpio <> "no" && rpm_is_available () &&
    (Config.yumdownloader <> "no" || Config.dnf <> "no") &&
    try
      (stat "/etc/redhat-release").st_kind = S_REG ||
      (stat "/etc/fedora-release").st_kind = S_REG
    with Unix_error _ -> false

let opensuse_detect () =
  Config.rpm <> "no" && Config.rpm2cpio <> "no" && rpm_is_available () &&
    Config.zypper <> "no" &&
    try (stat "/etc/SuSE-release").st_kind = S_REG with Unix_error _ -> false

let mageia_detect () =
  Config.rpm <> "no" && Config.rpm2cpio <> "no" && rpm_is_available () &&
    Config.urpmi <> "no" &&
    Config.fakeroot <> "no" &&
    try (stat "/etc/mageia-release").st_kind = S_REG with Unix_error _ -> false

let settings = ref no_settings
let rpm_major, rpm_minor = ref 0, ref 0
let zypper_major, zypper_minor, zypper_patch = ref 0, ref 0, ref 0
let t = ref None

let get_rpm () =
  match !t with
  | None ->
    eprintf "supermin: rpm: get_rpm called too early";
    exit 1
  | Some t -> t

let rec rpm_init s =
  settings := s;

  (* Get RPM version. We have to adjust some RPM commands based on
   * the version.
   *)
  let version = rpm_version () in
  let major, minor =
    match string_split "." version with
    | [] ->
      eprintf "supermin: unable to parse empty rpm version string\n";
      exit 1
    | [x] ->
      eprintf "supermin: unable to parse rpm version string: %s\n" x;
      exit 1
    | major :: minor :: _ ->
      try int_of_string major, int_of_string minor
      with Failure "int_of_string" ->
        eprintf "supermin: unable to parse rpm version string: non-numeric, %s\n" version;
        exit 1 in
  rpm_major := major;
  rpm_minor := minor;
  if !settings.debug >= 1 then
    printf "supermin: rpm: detected RPM version %d.%d\n" major minor;

  t := Some (rpm_open ~debug:!settings.debug)

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

let rpm_fini () =
  match !t with
  | None -> ()
  | Some t -> rpm_close t

(* Memo from package type to internal rpm_t. *)
let rpm_of_pkg, pkg_of_rpm = get_memo_functions ()

(* Memo of rpm_package_of_string. *)
let rpmh = Hashtbl.create 13

let rpm_package_of_string str =
  let query rpm =
    let rpms = Array.to_list (rpm_installed (get_rpm ()) rpm) in
    (* RPM will return multiple hits when either multiple versions or
     * multiple arches are installed at the same time.  We are only
     * interested in the highest version with the best
     * architecture.
     *)
    let cmp { version = v1; arch = a1 } { version = v2; arch = a2 } =
      let i = rpm_vercmp v2 v1 in
      if i <> 0 then i
      else compare_architecture a2 a1
    in
    let rpms = List.sort cmp rpms in
    List.hd rpms
  in

  try
    Hashtbl.find rpmh str
  with
    Not_found ->
      let r =
        try Some (pkg_of_rpm (query str))
        with Not_found ->
          try
            let p = rpm_pkg_whatprovides (get_rpm ()) str in
            (* Pick only a provided package when there is just one of them,
             * otherwise there is no reliable way to know which one to pick
             * if there are multiple providers.
             *)
            if Array.length p = 1 then
              Some (pkg_of_rpm (query p.(0)))
            else
              None
          with Not_found -> None in
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
  if is_rpm_lt_4_11 || rpm.epoch = 0 then
    sprintf "%s-%s-%s.%s" rpm.name rpm.version rpm.release rpm.arch
  else
    sprintf "%s-%d:%s-%s.%s"
      rpm.name rpm.epoch rpm.version rpm.release rpm.arch

let rpm_package_name pkg =
  let rpm = rpm_of_pkg pkg in
  rpm.name

let rpm_get_package_database_mtime () =
  (lstat "/var/lib/rpm/Packages").st_mtime

(* Memo of resolved provides. *)
let rpm_providers = Hashtbl.create 13

let rpm_get_all_requires pkgs =
  let get pkg =
    let reqs =
      try
        rpm_pkg_requires (get_rpm ()) pkg
      with
        Multiple_matches _ as ex ->
          match rpm_package_of_string pkg with
            | None -> raise ex
            | Some pkg ->
              rpm_pkg_requires (get_rpm ()) (rpm_package_to_string pkg) in
    let pkgs' = Array.fold_left (
      fun set x ->
        try
          let provides =
            try Hashtbl.find rpm_providers x
            with Not_found ->
              let p = rpm_pkg_whatprovides (get_rpm ()) x in
              Hashtbl.add rpm_providers x p;
              p in
          Array.fold_left (
            fun newset p ->
              match rpm_package_of_string p with
                | None -> newset
                | Some x -> StringSet.add p newset
          ) set provides
        with Not_found -> set
    ) StringSet.empty reqs in
    pkgs'
  in
  let queue = Queue.create () in
  let final = ref (stringset_of_list
                      (List.map rpm_package_name
                          (PackageSet.elements pkgs))) in
  StringSet.iter (fun x -> Queue.push x queue) !final;
  let resolved = ref StringSet.empty in
  while not (Queue.is_empty queue) do
    let current = Queue.pop queue in
    if not (StringSet.mem current !resolved) then (
      try
        let expanded = get current in
        let diff = StringSet.diff expanded !final in
        if not (StringSet.is_empty diff) then (
          final := StringSet.union !final diff;
          StringSet.iter (fun x -> Queue.push x queue) diff;
        )
      with Not_found -> ();
      resolved := StringSet.add current !resolved
    )
  done;
  let pkgs' = filter_map rpm_package_of_string (StringSet.elements !final) in
  package_set_of_list pkgs'

let rpm_get_all_files pkgs =
  let files_compare { filepath = a } { filepath = b } =
    compare a b in
  let files = List.map rpm_package_to_string (PackageSet.elements pkgs) in
  let files = List.fold_right (
    fun pkg xs ->
      let files = Array.to_list (rpm_pkg_filelist (get_rpm ()) pkg) in
      files @ xs
  ) files [] in
  let files = sort_uniq ~cmp:files_compare files in
  List.map (
    fun { filepath = path; filetype = flags } ->
      let config = flags = FileConfig in
      { ft_path = path; ft_source_path = path; ft_config = config }
  ) files

let rec fedora_download_all_packages pkgs dir =
  let tdir = !settings.tmpdir // string_random8 () in

  if Config.yumdownloader <> "no" then (
    (* It's quite complex to get yumdownloader to download specific
     * RPMs.  If we use the full NVR, then it will refuse if an installed
     * RPM is older than whatever is currently in the repo.  If we use
     * just name, it will download all architectures (even with
     * --archlist).
     * 
     * Use name.arch so it can download any version but only the specific
     * architecture.
     *)
    let rpms = pkgs_as_NA_rpms pkgs in

    let cmd =
      sprintf "%s%s%s --destdir %s %s"
        Config.yumdownloader
        (if !settings.debug >= 1 then "" else " --quiet")
        (match !settings.packager_config with
        | None -> ""
        | Some filename -> sprintf " -c %s" (quote filename))
        (quote tdir)
        (quoted_list rpms) in
    run_command cmd
  )
  else (* Config.dnf <> "no" *) (
    (* dnf doesn't create the download directory. *)
    mkdir tdir 0o700;

    let rpms = pkgs_as_NA_rpms pkgs in

    let cmd =
      sprintf "%s download --destdir %s %s"
        Config.dnf (quote tdir) (quoted_list rpms) in
    run_command cmd
  );

  rpm_unpack tdir dir

and opensuse_download_all_packages pkgs dir =
  let tdir = !settings.tmpdir // string_random8 () in

  let rpms = pkgs_as_NA_rpms pkgs in

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

and pkgs_as_NA_rpms pkgs =
  let rpms = List.map rpm_of_pkg (PackageSet.elements pkgs) in
  List.map (
    fun { name = name; arch = arch } ->
      sprintf "%s.%s" name arch
  ) rpms

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
    ph_fini = rpm_fini;
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
