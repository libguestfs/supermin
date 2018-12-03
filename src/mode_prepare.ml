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

open Printf

open Package_handler
open Utils

let prepare debug (copy_kernel, format, host_cpu,
             packager_config, tmpdir, use_installed, size,
             include_packagelist)
    inputs outputdir =
  if debug >= 1 then
    printf "supermin: prepare: %s\n%!" (String.concat " " inputs);

  if inputs = [] then
    error "prepare: no input packages specified";

  let ph = get_package_handler () in

  (* Resolve the package names supplied by the user.  Since
   * ph_package_of_string returns None if a package is not installed,
   * filter_map will return only packages which are installed.
   *)
  let packages = filter_map ph.ph_package_of_string inputs in
  if packages = [] then
    error "prepare: none of the packages listed on the command line seem to be installed";

  if debug >= 1 then (
    printf "supermin: packages specified on the command line:\n";
    List.iter (printf "  - %s\n") (List.map ph.ph_package_to_string packages);
    flush stdout
  );

  (* Convert input packages to a set.  This removes duplicates. *)
  let packages = package_set_of_list packages in

  (* Write input packages to the 'packages' file.  We don't need to
   * write the dependencies because we do dependency resolution at
   * build time too.
   *)
  let () =
    let packages = PackageSet.elements packages in
    let pkg_names = List.map ph.ph_package_name packages in
    let pkg_names = List.sort compare pkg_names in

    let packages_file = outputdir // "packages" in
    if debug >= 1 then
      printf "supermin: writing %s\n%!" packages_file;

    let chan = open_out packages_file in
    List.iter (fprintf chan "%s\n") pkg_names;
    close_out chan in

  (* Resolve the dependencies. *)
  let packages = get_all_requires packages in

  if debug >= 1 then (
    printf "supermin: after resolving dependencies there are %d packages:\n"
      (PackageSet.cardinal packages);
    let pkg_names = PackageSet.elements packages in
    let pkg_names = List.map ph.ph_package_to_string pkg_names in
    let pkg_names = List.sort compare pkg_names in
    List.iter (printf "  - %s\n") pkg_names;
    flush stdout
  );

  (* List the files in each package. *)
  let packages =
    PackageSet.fold (
      fun pkg pkgs ->
        let files = get_files pkg in
        (pkg, files) :: pkgs
    ) packages [] in

  if debug >= 2 then (
    List.iter (
      fun (pkg, files) ->
        printf "supermin: files in '%s':\n" (ph.ph_package_to_string pkg);
        List.iter
          (fun { ft_path = path; ft_config = config } ->
            printf "  - %s%s\n" path (if config then " [config]" else ""))
          files
    ) packages;
    flush stdout
  );

  let dir =
    if not use_installed then (
      (* For packages that contain any config files, we have to download
       * the original package, in order to construct the base image.  We
       * can skip packages that have no config files.
       *)
      let dir = tmpdir // "prepare.d" in
      Unix.mkdir dir 0o755;

      let () =
        let dl_packages = filter_map (
          fun (pkg, files) ->
            let has_config_files =
              List.exists (fun { ft_config = config } -> config) files in
            if has_config_files then Some pkg else None
        ) packages in
        let dl_packages = package_set_of_list dl_packages in
        download_all_packages dl_packages dir in

      dir
    )
    else (* --use-installed *) "/" in

  (* Get the list of config files, which are the files we will place
   * into base.  We have to check the files exist too, since they can
   * be missing either from the package or from the filesystem (the
   * latter case with --use-installed).
   *)
  let config_files =
    List.map (
      fun (_, files) ->
        filter_map (
          function
          | { ft_config = true; ft_path = path } -> Some path
          | { ft_config = false } -> None
        ) files
    ) packages in
  let config_files = List.flatten config_files in

  let config_files = List.filter (
    fun path ->
      try close_in (open_in (dir // path)); true
      with Sys_error _ -> false
  ) config_files in

  if debug >= 1 then
    printf "supermin: there are %d config files\n"
           (List.length config_files);

  if config_files <> [] then (
    (* There are config files to copy, so create the list with them,
     * and then compress them with tar.
     *)
    let files_from =
      (* Put the list of config files into a file, for tar to read. *)
      let files_from = tmpdir // "files-from.txt" in
      let chan = open_out files_from in
      List.iter (fprintf chan ".%s\n") config_files; (* "./filename" *)
      close_out chan;

      files_from in

    (* Write base.tar.gz. *)
    let base = outputdir // "base.tar.gz" in
    if debug >= 1 then printf "supermin: writing %s\n%!" base;
    let cmd =
      sprintf "tar%s -C %s -zcf %s -T %s"
              (if debug >=1 then " -v" else "")
              (quote dir) (quote base) (quote files_from) in
    run_command cmd;
  )
  else (
    (* No config files to copy, so do not create base.tar.gz. *)
    if debug >= 1 then printf "supermin: not creating base.tar.gz\n%!";
  )
