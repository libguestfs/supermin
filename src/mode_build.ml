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
open Types
open Package_handler
open Fnmatch
open Glob
open Realpath

type appliance = {
  excludefiles : string list;           (* list of wildcards *)
  hostfiles : string list;              (* list of wildcards *)
  packages : string list;               (* list of package names *)
  (* Note that base images don't appear here because they are unpacked
   * into a build directory as we discover them.
   *)
}

let empty_appliance = { excludefiles = []; hostfiles = []; packages = [] }

type file_type =
| GZip of file_content
| XZ of file_content
| Uncompressed of file_content
and file_content =
| Base_image                            (* a tarball *)
| Packages
| Hostfiles
| Excludefiles
| Empty

let rec string_of_file_type = function
  | GZip c -> sprintf "gzip %s" (string_of_file_content c)
  | XZ c -> sprintf "xz %s" (string_of_file_content c)
  | Uncompressed c -> sprintf "uncompressed %s" (string_of_file_content c)
and string_of_file_content = function
  | Base_image -> "base image (tar)"
  | Packages -> "packages"
  | Hostfiles -> "hostfiles"
  | Excludefiles -> "excludefiles"
  | Empty -> "empty"

let kernel_filename = "kernel"
and appliance_filename = "root"
and initrd_filename = "initrd"

let rec build debug
    (copy_kernel, format, host_cpu,
     packager_config, tmpdir, use_installed, size,
     include_packagelist)
    inputs outputdir =
  if debug >= 1 then
    printf "supermin: build: %s\n%!" (String.concat " " inputs);

  if inputs = [] then
    error "build: no input supermin appliance specified";

  (* When base images are seen, they are unpacked into this temporary
   * directory.  But to speed things up, when we are building a chroot,
   * set the basedir to be the output directory, so we avoid copying
   * from a temporary directory to the output directory.
   *)
  let basedir =
    match format with
    | Chroot ->
      outputdir
    | Ext2 ->
      let basedir = tmpdir // "base.d" in
      mkdir basedir 0o755;
      basedir in

  (* Read the supermin appliance, ie. the input files and/or
   * directories that make up the appliance.
   *)
  if debug >= 1 then
    printf "supermin: reading the supermin appliance\n%!";
  let appliance = read_appliance debug basedir empty_appliance inputs in

  (* Resolve dependencies in the list of packages. *)
  let ph = get_package_handler () in
  if debug >= 1 then
    printf "supermin: mapping package names to installed packages\n%!";
  let packages = filter_map ph.ph_package_of_string appliance.packages in
  if debug >= 1 then
    printf "supermin: resolving full list of package dependencies\n%!";
  let packages =
    let packages = package_set_of_list packages in
    get_all_requires packages in

  (* Get the list of packages only if we need to, i.e. when creating
   * /packagelist in the appliance, when printing all the packages
   * for debug, or in both cases.
   *)
  let pretty_packages =
    if include_packagelist || debug >= 2 then (
      let pkg_names = PackageSet.elements packages in
      let pkg_names = List.map ph.ph_package_to_string pkg_names in
      List.sort compare pkg_names
    ) else [] in

  if debug >= 1 then (
    printf "supermin: build: %d packages, including dependencies\n%!"
      (PackageSet.cardinal packages);
    if debug >= 2 then (
      List.iter (printf "  - %s\n") pretty_packages;
      flush Pervasives.stdout
    )
  );

  (* List the files in each package.  We only want to copy non-config
   * files to the full appliance, since config files are included in
   * the base image that we saved when preparing the supermin
   * appliance.
   *)
  let files = get_all_files packages in
  let files =
    List.filter (fun file -> not file.ft_config) files in

  if debug >= 1 then
    printf "supermin: build: %d files\n%!" (List.length files);

  (* Remove excludefiles from the list.  Notes: (1) The current
   * implementation does not apply excludefiles to the base image.  (2)
   * The current implementation does not apply excludefiles to the
   * hostfiles (see below).
   *)
  let files =
    if appliance.excludefiles = [] then files
    else (
      let fn_flags = [FNM_NOESCAPE] in
      List.filter (
        fun { ft_path = path } ->
          let include_ =
            List.for_all (
              fun pattern -> not (fnmatch pattern path fn_flags)
            ) appliance.excludefiles in
          if debug >= 2 && not include_ then
	    printf "supermin: build: excluding %s\n%!" path;
          include_
      ) files
    ) in

  if debug >= 1 then
    printf "supermin: build: %d files, after matching excludefiles\n%!"
      (List.length files);

  (* Add hostfiles.  This may contain wildcards too. *)
  let files =
    if appliance.hostfiles = [] then files
    else (
      let hostfiles = List.map (
        fun pattern -> glob pattern [GLOB_NOESCAPE]
      ) appliance.hostfiles in
      let hostfiles = List.map Array.to_list hostfiles in
      let hostfiles = List.flatten hostfiles in
      let hostfiles = List.map (
        fun path -> {ft_path = path; ft_source_path = path; ft_config = false}
      ) hostfiles in
      files @ hostfiles
    ) in

  if debug >= 1 then
    printf "supermin: build: %d files, after adding hostfiles\n%!"
      (List.length files);

  (* Remove files from the list which don't exist on the host or are
   * unreadable to us.
   *)
  let files =
    List.filter (
      fun file ->
        try ignore (lstat file.ft_source_path); true
        with Unix_error _ ->
          try ignore (lstat file.ft_path); true
          with Unix_error _ -> false
    ) files in

  if debug >= 1 then
    printf "supermin: build: %d files, after removing unreadable files\n%!"
      (List.length files);

  (* Difficult to explain what this does.  See comment below. *)
  let files = munge files in

  if debug >= 1 then (
    printf "supermin: build: %d files, after munging\n%!"
      (List.length files);
    if debug >= 2 then (
      List.iter (fun { ft_path = path } -> printf "  - %s\n" path) files;
      flush Pervasives.stdout
    )
  );

  (* Create a temporary file for packagelist, if requested. *)
  let packagelist_file =
    if include_packagelist then (
      let filename = tmpdir // "packagelist" in
      let chan = open_out filename in
      List.iter (fprintf chan "%s\n") pretty_packages;
      close_out chan;
      Some filename
    ) else None in

  (* Depending on the format, we build the appliance in different ways. *)
  (match format with
  | Chroot ->
    (* chroot doesn't need an external kernel or initrd *)
    Format_chroot.build_chroot debug files outputdir packagelist_file

  | Ext2 ->
    let kernel = outputdir // kernel_filename
    and appliance = outputdir // appliance_filename
    and initrd = outputdir // initrd_filename in
    let kernel_version, modpath =
      Format_ext2_kernel.build_kernel debug host_cpu copy_kernel kernel in
    Format_ext2.build_ext2 debug basedir files modpath kernel_version
                           appliance size packagelist_file;
    Format_ext2_initrd.build_initrd debug tmpdir modpath initrd
  )

and read_appliance debug basedir appliance = function
  | [] -> appliance

  | dir :: rest when Sys.is_directory dir ->
    let inputs = Array.to_list (Sys.readdir dir) in
    let inputs = List.sort compare inputs in
    let inputs = List.map ((//) dir) inputs in
    read_appliance debug basedir appliance (inputs @ rest)

  | file :: rest ->
    let file_type = get_file_type file in

    if debug >= 1 then
      printf "supermin: build: visiting %s type %s\n%!"
        file (string_of_file_type file_type);

    (* Depending on the file type, read or unpack the file. *)
    let appliance =
      match file_type with
      | Uncompressed Empty | GZip Empty | XZ Empty ->
        appliance
      | Uncompressed ((Packages|Hostfiles|Excludefiles) as t) ->
        let chan = open_in file in
        let lines = input_all_lines chan in
        close_in chan;
        update_appliance appliance lines t
      | GZip ((Packages|Hostfiles|Excludefiles) as t) ->
        let cmd = sprintf "zcat %s" (quote file) in
        let lines = run_command_get_lines cmd in
        update_appliance appliance lines t
      | XZ ((Packages|Hostfiles|Excludefiles) as t) ->
        let cmd = sprintf "xzcat %s" (quote file) in
        let lines = run_command_get_lines cmd in
        update_appliance appliance lines t
      | Uncompressed Base_image ->
        let cmd = sprintf "tar -C %s -xf %s" (quote basedir) (quote file) in
        run_command cmd;
        appliance
      | GZip Base_image ->
        let cmd =
          sprintf "zcat %s | tar -C %s -xf -" (quote file) (quote basedir) in
        run_command cmd;
        appliance
      | XZ Base_image ->
        let cmd =
          sprintf "xzcat %s | tar -C %s -xf -" (quote file) (quote basedir) in
        run_command cmd;
        appliance in

    read_appliance debug basedir appliance rest

and update_appliance appliance lines = function
  | Packages ->
    { appliance with packages = appliance.packages @ lines }
  | Hostfiles ->
    { appliance with hostfiles = appliance.hostfiles @ lines }
  | Excludefiles ->
    let lines = List.map (
      fun path ->
        let n = String.length path in
        if n < 1 || path.[0] <> '-' then
          error "excludefiles line does not start with '-'";
        String.sub path 1 (n-1)
    ) lines in
    { appliance with excludefiles = appliance.excludefiles @ lines }
  | Base_image | Empty -> assert false

(* Determine the [file_type] of [file], or exit with an error. *)
and get_file_type file =
  let chan = open_in file in
  let buf = Bytes.create 512 in
  let len = input chan buf 0 (Bytes.length buf) in
  close_in chan;
  let buf = Bytes.to_string buf in

  if len >= 3 && buf.[0] = '\x1f' && buf.[1] = '\x8b' && buf.[2] = '\x08'
  then                                  (* gzip-compressed file *)
    GZip (get_compressed_file_content "zcat" file)
  else if len >= 6 && buf.[0] = '\xfd' && buf.[1] = '7' && buf.[2] = 'z' &&
      buf.[3] = 'X' && buf.[4] = 'Z' && buf.[5] = '\000'
  then                                  (* xz-compressed file *)
    XZ (get_compressed_file_content "xzcat" file)
  else
    Uncompressed (get_file_content file buf len)

and get_file_content file buf len =
  if len >= 262 && buf.[257] = 'u' && buf.[258] = 's' &&
      buf.[259] = 't' && buf.[260] = 'a' && buf.[261] = 'r'
  then                                  (* tar file *)
    Base_image
  else if len >= 6 &&
      buf.[0] = '0' && buf.[1] = '7' &&
      buf.[2] = '0' && buf.[3] = '7' &&
      buf.[4] = '0' && buf.[5] = '1' then (
    (* However we intend to support them in future for both input
     * and output.
     *)
    error "%s: cpio files are not supported in this version of supermin" file;
  )
  else if len >= 2 && buf.[0] = '/' then Hostfiles
  else if len >= 2 && buf.[0] = '-' then Excludefiles
  else if len >= 1 && isalnum buf.[0] then Packages
  else if len = 0 then Empty
  else error "%s: unknown file type in supermin directory" file

and get_compressed_file_content zcat file =
  let cmd = sprintf "%s %s" zcat (quote file) in
  let chan_out, chan_in, chan_err = open_process_full cmd (environment ()) in
  let buf = Bytes.create 512 in
  let len = input chan_out buf 0 (Bytes.length buf) in
  let buf = Bytes.to_string buf in
  (* We're expecting the subprocess to fail because we close the pipe
   * early, so:
   *)
  ignore (Unix.close_process_full (chan_out, chan_in, chan_err));

  get_file_content file buf len

(* The files may not be listed in an order that allows us to run
 * through the list (even if we sorted it).  The particular problem is
 * where you have:
 *
 * - /lib is a symlink to /usr/lib
 * - /lib/modules exists
 * - /usr/lib
 *
 * The problem is that /lib is created as a symlink to a directory
 * that doesn't yet exist (/usr/lib), and so it fails when you
 * try to create /lib/modules (ie. really /usr/lib/modules).
 *
 * A second problem is that intermediate directories are not
 * necessarily listed.  eg. "/foo/bar/baz" might appear, without the
 * parent directories appearing in the list.  This can happen
 * because of excludefiles, or simply packaging mistakes in
 * the distro.
 *
 * We create intermediate directories simply by examining the
 * file list.  Symlinks to not-yet-existing directories are
 * handled by adding the target directory into the list before the
 * symlink.
 *)
and munge files =
  let files =
    List.sort (fun f1 f2 -> compare f1.ft_path f2.ft_path) files in

  let rec stat_is_dir dir =
    try (stat dir).st_kind = S_DIR with Unix_error _ -> false
  and is_lnk_to_dir dir =
    try stat_is_dir dir && (lstat dir).st_kind = S_LNK
    with Unix_error _ -> false
  in

  let insert_dir, dir_seen =
    let h = Hashtbl.create (List.length files) in
    let insert_dir dir = Hashtbl.replace h dir true in
    let dir_seen dir = Hashtbl.mem h dir in
    insert_dir, dir_seen
  in

  let rec loop = function
    | [] -> []

    | { ft_path = "/" } :: rest ->
      (* This is just to avoid a corner-case in subsequent rules. *)
      insert_dir "/";
      loop rest

    | dir :: rest when stat_is_dir dir.ft_path && dir_seen dir.ft_path ->
      dir :: loop rest

    | dir :: rest when is_lnk_to_dir dir.ft_path ->
      insert_dir dir.ft_path;

      (* Symlink to a directory.  Insert the target directory before
       * if we've not seen it yet.
       *)
      let target = readlink dir.ft_path in
      let parent = Filename.dirname dir.ft_path in
      (* Make the target an absolute path. *)
      let target =
        if String.length target < 1 || target.[0] <> '/' then
          realpath (parent // target)
        else
          target in
      (* Remove trailing slash from filenames (RHBZ#1155586). *)
      let target =
        let len = String.length target in
        if len >= 2 && target.[len-1] = '/' then
          String.sub target 0 (len-1)
        else
          target in
      if not (dir_seen target) then (
        let target =
          {ft_path = target; ft_source_path = target; ft_config = false} in
        loop (target :: dir :: rest)
      )
      else
        dir :: loop rest

    | dir :: rest when stat_is_dir dir.ft_path ->
      insert_dir dir.ft_path;

      (* Have we seen the parent? *)
      let parent = Filename.dirname dir.ft_path in
      if not (dir_seen parent) then (
        let parent =
          {ft_path = parent; ft_source_path = parent; ft_config = false} in
        loop (parent :: dir :: rest)
      )
      else
        dir :: loop rest

    | file :: rest ->
      (* Have we seen this parent directory before? *)
      let dir = Filename.dirname file.ft_path in
      if not (dir_seen dir) then (
        let dir = {ft_path = dir; ft_source_path = dir; ft_config = false} in
        loop (dir :: file :: rest)
      )
      else
        file :: loop rest
  in
  let files = loop files in

  files

and get_outputs
    (copy_kernel, format, host_cpu,
     packager_config, tmpdir, use_installed, size,
     include_packagelist)
    inputs =
  match format with
  | Chroot ->
    (* The content for chroot depends on the packages. *)
    []
  | Ext2 ->
    [kernel_filename; appliance_filename; initrd_filename]
