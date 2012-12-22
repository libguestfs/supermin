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

(* Yum and RPM support. *)

open Unix
open Printf

open Febootstrap_package_handlers
open Febootstrap_utils
open Febootstrap_cmdline

(* Create a temporary directory for use by all the functions in this file. *)
let tmpdir = tmpdir ()

let yum_rpm_detect () =
  (file_exists "/etc/redhat-release" || file_exists "/etc/fedora-release") &&
    Config.yum <> "no" && Config.rpm <> "no"

let yum_rpm_init () =
  if use_installed then
    failwith "yum_rpm driver doesn't support --use-installed"

let yum_rpm_resolve_dependencies_and_download names =
  (* Liberate this data from python. *)
  let tmpfile = tmpdir // "names.tmp" in
  let py = sprintf "
import yum
import yum.misc
import sys

verbose = %d

if verbose:
    print \"febootstrap_yum_rpm: running python code to query yum and resolve deps\"

yb = yum.YumBase ()
yb.preconf.debuglevel = verbose
yb.preconf.errorlevel = verbose
try:
    yb.prerepoconf.multi_progressbar = None
except:
    pass
if %s:
    yb.preconf.fn = %S
try:
    yb.setCacheDir ()
except AttributeError:
    pass

if verbose:
    print \"febootstrap_yum_rpm: looking up the base packages from the command line\"
deps = dict ()
pkgs = yb.pkgSack.returnPackages (patterns=sys.argv[1:])
for pkg in pkgs:
    deps[pkg] = False

if verbose:
    print \"febootstrap_yum_rpm: recursively finding all the dependencies\"
stable = False
while not stable:
    stable = True
    for pkg in deps.keys():
        if deps[pkg] == False:
            deps[pkg] = []
            stable = False
            if verbose:
                print (\"febootstrap_yum_rpm: examining deps of %%s\" %%
                       pkg.name)
            for r in pkg.requires:
                ps = yb.whatProvides (r[0], r[1], r[2])
                best = yb._bestPackageFromList (ps.returnPackages ())
                if best and best.name != pkg.name:
                    deps[pkg].append (best)
                    if not deps.has_key (best):
                        deps[best] = False
            deps[pkg] = yum.misc.unique (deps[pkg])

# Write it to a file because yum spews garbage on stdout.
f = open (%S, \"w\")
for pkg in deps.keys ():
    f.write (\"%%s %%s %%s %%s %%s\\n\" %%
             (pkg.name, pkg.epoch, pkg.version, pkg.release, pkg.arch))
f.close ()

if verbose:
    print \"febootstrap_yum_rpm: finished python code\"
"
    (if verbose then 1 else 0)
    (match packager_config with None -> "False" | Some _ -> "True")
    (match packager_config with None -> "" | Some filename -> filename)
    tmpfile in
  run_python py names;
  let chan = open_in tmpfile in
  let lines = input_all_lines chan in
  close_in chan;

  (* Get fields. *)
  let pkgs =
    List.map (
      fun line ->
        match string_split " " line with
        | [name; epoch; version; release; arch] ->
            name, int_of_string epoch, version, release, arch
        | _ ->
            eprintf "febootstrap: bad output from python script: '%s'" line;
            exit 1
    ) lines in

  (* Something of a hack for x86_64: exclude all i[3456]86 packages. *)
  let pkgs =
    if Config.host_cpu = "x86_64" then (
      List.filter (
        function (_, _, _, _, ("i386"|"i486"|"i586"|"i686")) -> false
        | _ -> true
      ) pkgs
    )
    else pkgs in

  (* Exclude packages matching [--exclude] regexps on the command line. *)
  let pkgs =
    List.filter (
      fun (name, _, _, _, _) ->
        not (List.exists (fun re -> Str.string_match re name 0) excludes)
    ) pkgs in

  (* Sort the list of packages, and remove duplicates (by name).
   * XXX This is not quite right: we really want to keep the latest
   * package if duplicates are found, but that would require a full
   * version compare function.
   *)
  let pkgs = List.sort (fun a b -> compare b a) pkgs in
  let pkgs =
    let cmp (name1, _, _, _, _) (name2, _, _, _, _) = compare name1 name2 in
    uniq ~cmp pkgs in
  let pkgs = List.sort compare pkgs in

  (* Construct package names. *)
  let pkgnames = List.map (
    function
    | name, 0, version, release, arch ->
        sprintf "%s-%s-%s.%s" name version release arch
    | name, epoch, version, release, arch ->
        sprintf "%d:%s-%s-%s.%s" epoch name version release arch
  ) pkgs in

  if pkgnames = [] then (
    eprintf "febootstrap: yum-rpm: error: no packages to download\n";
    exit 1
  );

  let cmd = sprintf "yumdownloader%s%s --destdir %s %s"
    (if verbose then "" else " --quiet")
    (match packager_config with None -> ""
     | Some filename -> sprintf " -c %s" filename)
    (Filename.quote tmpdir)
    (String.concat " " (List.map Filename.quote pkgnames)) in
  run_command cmd;

  (* Return list of package filenames. *)
  List.map (
    (* yumdownloader doesn't include epoch in the filename *)
    fun (name, _, version, release, arch) ->
      sprintf "%s/%s-%s-%s.%s.rpm" tmpdir name version release arch
  ) pkgs

let rec yum_rpm_list_files pkg =
  (* Run rpm -qlp with some extra magic. *)
  let cmd =
    sprintf "rpm -q --qf '[%%{FILENAMES} %%{FILEFLAGS:fflags} %%{FILEMODES} %%{FILESIZES}\\n]' -p %s"
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
            else
              Some (filename, {
                      ft_dir = mode land 0o40000 <> 0;
                      ft_ghost = test_flag 'g'; ft_config = test_flag 'c';
                      ft_mode = mode; ft_size = size;
                    })
        | _ ->
            eprintf "febootstrap: bad output from rpm command: '%s'" line;
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

let yum_rpm_get_file_from_package pkg file =
  debug "extracting %s from %s ..." file (Filename.basename pkg);

  let outfile = tmpdir // file in
  let cmd =
    sprintf "umask 0000; rpm2cpio %s | (cd %s && cpio --quiet -id .%s)"
      (Filename.quote pkg) (Filename.quote tmpdir) (Filename.quote file) in
  run_command cmd;
  outfile

let () =
  let ph = {
    ph_detect = yum_rpm_detect;
    ph_init = yum_rpm_init;
    ph_resolve_dependencies_and_download =
      yum_rpm_resolve_dependencies_and_download;
    ph_list_files = yum_rpm_list_files;
    ph_get_file_from_package = yum_rpm_get_file_from_package;
  } in
  register_package_handler "yum-rpm" ph
