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

open Unix
open Printf

open Febootstrap_package_handlers
open Febootstrap_utils
open Febootstrap_cmdline

(* Create a temporary directory for use by all the functions in this file. *)
let tmpdir = tmpdir ()

let () =
  debug "%s %s" Config.package_name Config.package_version;

  (* Instead of printing out warnings as we go along, accumulate them
   * in lists and print them all out at the end.
   *)
  let warn_unreadable = ref [] in

  (* Determine which package manager this system uses. *)
  check_system ();
  let ph = get_package_handler () in

  debug "selected package handler: %s" (get_package_handler_name ());

  (* Not --names: check files exist. *)
  if not names_mode then (
    List.iter (
      fun pkg ->
        if not (file_exists pkg) then (
          eprintf "febootstrap: %s: no such file (did you miss out the --names option?)\n" pkg;
          exit 1
        )
    ) packages
  );

  (* --names: resolve the package list to a full list of package names
   * (including dependencies).
   *)
  let packages =
    if names_mode then (
      let packages = ph.ph_resolve_dependencies_and_download packages in
      debug "resolved packages: %s" (String.concat " " packages);
      packages
    )
    else packages in

  (* Get the list of files. *)
  let files =
    List.flatten (
      List.map (
        fun pkg ->
          let files = ph.ph_list_files pkg in
          List.map (fun (filename, ft) -> filename, ft, pkg) files
      ) packages
    ) in

  (* Canonicalize the name of directories, so that /a and /a/ are the same. *)
  let files =
    List.map (
      fun (filename, ft, pkg) ->
        let len = String.length filename in
        let filename =
          if len > 1 (* don't rewrite "/" *) && ft.ft_dir
            && filename.[len-1] = '/' then
              String.sub filename 0 (len-1)
          else
            filename in
        (filename, ft, pkg)
    ) files in

  (* Sort and combine duplicate files. *)
  let files =
    let files = List.sort compare files in

    let combine (name1, ft1, pkg1) (name2, ft2, pkg2) =
      (* Rules for combining files. *)
      if ft1.ft_config || ft2.ft_config then (
	(* It's a fairly frequent bug in Fedora for two packages to
	 * incorrectly list the same config file.  Allow this, provided
	 * the size of both files is 0.
	 *)
	if ft1.ft_size = 0 && ft2.ft_size = 0 then
	  (name1, ft1, pkg1)
	else (
          eprintf "febootstrap: error: %s is a config file which is listed in two packages (%s, %s)\n"
            name1 pkg1 pkg2;
          exit 1
	)
      )
      else if (ft1.ft_dir || ft2.ft_dir) && (not (ft1.ft_dir && ft2.ft_dir)) then (
        eprintf "febootstrap: error: %s appears as both directory and ordinary file (%s, %s)\n"
          name1 pkg1 pkg2;
        exit 1
      )
      else if ft1.ft_ghost then
        (name2, ft2, pkg2)
      else
        (name1, ft1, pkg1)
    in

    let rec loop = function
      | [] -> []
      | (name1, _, _ as f1) :: (name2, _, _ as f2) :: fs when name1 = name2 ->
          let f = combine f1 f2 in loop (f :: fs)
      | f :: fs -> f :: loop fs
    in
    loop files in

  (* Because we may have excluded some packages, and also because of
   * distribution packaging errors, it's not necessarily true that a
   * directory is created before each file in that directory.
   * Determine those missing directories and add them now.
   *)
  let files =
    let insert_dir, dir_seen =
      let h = Hashtbl.create (List.length files) in
      let insert_dir dir = Hashtbl.replace h dir true in
      let dir_seen dir = Hashtbl.mem h dir in
      insert_dir, dir_seen
    in
    let files =
      List.map (
        fun (path, { ft_dir = is_dir }, _ as f) ->
          if is_dir then
            insert_dir path;

          let rec loop path =
            let parent = Filename.dirname path in
            if dir_seen parent then []
            else (
              insert_dir parent;
              let newdir = (parent, { ft_dir = true; ft_config = false;
                                      ft_ghost = false; ft_mode = 0o40755;
				      ft_size = 0 },
                            "") in
              newdir :: loop parent
            )
          in
          List.rev (f :: loop path)
      ) files in
    List.flatten files in

  (* Debugging. *)
  debug "%d files and directories" (List.length files);
  if false then (
    List.iter (
      fun (name, { ft_dir = dir; ft_ghost = ghost; ft_config = config;
                   ft_mode = mode; ft_size = size }, pkg) ->
        printf "%s [%s%s%s%o %d] from %s\n" name
          (if dir then "dir " else "")
          (if ghost then "ghost " else "")
          (if config then "config " else "")
          mode size
          pkg
    ) files
  );

  (* Split the list of files into ones for hostfiles and ones for base image. *)
  let p_hmac = Str.regexp "^\\..*\\.hmac$" in

  let hostfiles = ref []
  and baseimgfiles = ref [] in
  List.iter (
    fun (path, {ft_dir = dir; ft_ghost = ghost; ft_config = config} ,_ as f) ->
      let file = Filename.basename path in

      (* Ignore boot files, kernel, kernel modules.  Supermin appliances
       * are booted from external kernel and initrd, and
       * febootstrap-supermin-helper copies the host kernel modules.
       * Note we want to keep the /boot and /lib/modules directory entries.
       *)
      if string_prefix "/boot/" path then ()
      else if string_prefix "/lib/modules/" path then ()

      (* Always write directory names to both output files. *)
      else if dir then (
        hostfiles := f :: !hostfiles;
        baseimgfiles := f :: !baseimgfiles;
      )

      (* Timezone configuration is config, but copy it from host system. *)
      else if path = "/etc/localtime" then
        hostfiles := f :: !hostfiles

      (* Ignore FIPS files (.*.hmac) (RHBZ#654638). *)
      else if Str.string_match p_hmac file 0 then ()

      (* Ghost files are created empty in the base image. *)
      else if ghost then
        baseimgfiles := f :: !baseimgfiles

      (* For config files we can't rely on the host-installed copy
       * since the admin may have modified then.  We have to get the
       * original file from the package and put it in the base image.
       *)
      else if config then
        baseimgfiles := f :: !baseimgfiles

      (* Anything else comes from the host. *)
      else
        hostfiles := f :: !hostfiles
  ) files;
  let hostfiles = List.rev !hostfiles
  and baseimgfiles = List.rev !baseimgfiles in

  (* Write hostfiles. *)

  (* Regexps used below. *)
  let p_ld_so = Str.regexp "^ld-[.0-9]+\\.so$" in
  let p_libbfd = Str.regexp "^libbfd-.*\\.so$" in
  let p_libgcc = Str.regexp "^libgcc_s-.*\\.so\\.\\([0-9]+\\)$" in
  let p_libntfs3g = Str.regexp "^libntfs-3g\\.so\\..*$" in
  let p_lib123so = Str.regexp "^lib\\(.*\\)-[-.0-9]+\\.so$" in
  let p_lib123so123 =
    Str.regexp "^lib\\(.*\\)-[-.0-9]+\\.so\\.\\([0-9]+\\)\\." in
  let p_libso123 = Str.regexp "^lib\\(.*\\)\\.so\\.\\([0-9]+\\)\\." in
  let ntfs3g_once = ref false in

  let chan = open_out (tmpdir // "hostfiles") in
  List.iter (
    fun (path, {ft_dir = is_dir; ft_ghost = ghost; ft_config = config;
                ft_mode = mode }, _) ->
      let dir = Filename.dirname path in
      let file = Filename.basename path in

      if is_dir then
        fprintf chan "%s\n" path

      (* Warn about hostfiles which are unreadable by non-root.  We
       * won't be able to add those to the appliance at run time, but
       * there's not much else we can do about it except get the
       * distros to fix this nonsense.
       *)
      else if mode land 0o004 = 0 then
        warn_unreadable := path :: !warn_unreadable

      (* Replace fixed numbers in some library names by wildcards. *)
      else if Str.string_match p_ld_so file 0 then
        fprintf chan "%s/ld-*.so\n" dir

      (* Special case for libbfd. *)
      else if Str.string_match p_libbfd file 0 then
        fprintf chan "%s/libbfd-*.so\n" dir

      (* Special case for libgcc_s-<gccversion>-<date>.so.N *)
      else if Str.string_match p_libgcc file 0 then
        fprintf chan "%s/libgcc_s-*.so.%s\n" dir (Str.matched_group 1 file)

      (* Special case for libntfs-3g.so.* *)
      else if Str.string_match p_libntfs3g file 0 then (
        if not !ntfs3g_once then (
          fprintf chan "%s/libntfs-3g.so.*\n" dir;
          ntfs3g_once := true
        )
      )

      (* libfoo-1.2.3.so *)
      else if Str.string_match p_lib123so file 0 then
        fprintf chan "%s/lib%s-*.so\n" dir (Str.matched_group 1 file)

      (* libfoo-1.2.3.so.123 (but NOT '*.so.N') *)
      else if Str.string_match p_lib123so123 file 0 then
        fprintf chan "%s/lib%s-*.so.%s.*\n" dir
          (Str.matched_group 1 file) (Str.matched_group 2 file)

      (* libfoo.so.1.2.3 (but NOT '*.so.N') *)
      else if Str.string_match p_libso123 file 0 then
        fprintf chan "%s/lib%s.so.%s.*\n" dir
          (Str.matched_group 1 file) (Str.matched_group 2 file)

      (* Anything else comes from the host. *)
      else
        fprintf chan "%s\n" path
  ) hostfiles;
  close_out chan;

  (* Write base.img.
   *
   * We have to create directories and copy files to tmpdir/root
   * and then call out to cpio to construct the initrd.
   *)
  let rootdir = tmpdir // "root" in
  mkdir rootdir 0o755;
  List.iter (
    fun (path, { ft_dir = is_dir; ft_ghost = ghost; ft_config = config;
                 ft_mode = mode }, pkg) ->
      (* Always write directory names to both output files. *)
      if is_dir then (
        (* Directory permissions are fixed up below. *)
        if path <> "/" then mkdir (rootdir // path) 0o755
      )

      (* Ghost files are just touched with the correct perms. *)
      else if ghost then (
        let chan = open_out (rootdir // path) in
        close_out chan;
        chmod (rootdir // path) (mode land 0o777 lor 0o400)
      )

      (* For config files we can't rely on the host-installed copy
       * since the admin may have modified it.  We have to get the
       * original file from the package.
       *)
      else if config then (
        let outfile = ph.ph_get_file_from_package pkg path in

        (* Note that the output config file might not be a regular file. *)
        let statbuf = lstat outfile in

        let destfile = rootdir // path in

        (* Depending on the file type, copy it to destination. *)
        match statbuf.st_kind with
        | S_REG ->
            (* Unreadable files (eg. /etc/gshadow).  Make readable. *)
            if statbuf.st_perm = 0 then chmod outfile 0o400;
            let cmd =
              sprintf "cp %s %s"
                (Filename.quote outfile) (Filename.quote destfile) in
            run_command cmd;
            chmod destfile (mode land 0o777 lor 0o400)
        | S_LNK ->
            let link = readlink outfile in
            symlink link destfile
        | S_DIR -> assert false
        | S_CHR
        | S_BLK
        | S_FIFO
        | S_SOCK ->
            eprintf "febootstrap: error: %s: don't know how to handle this type of file\n" path;
            exit 1
      )

      else
        assert false (* should not be reached *)
  ) baseimgfiles;

  (* Fix up directory permissions, in reverse order.  Since we don't
   * want to have a read-only directory that we can't write into above.
   *)
  List.iter (
    fun (path, { ft_dir = is_dir; ft_mode = mode }, _) ->
      if is_dir then chmod (rootdir // path) (mode land 0o777 lor 0o700)
  ) (List.rev baseimgfiles);

  (* Construct the 'base.img' initramfs.  Feed in the list of filenames
   * partly because we conveniently have them, and partly because
   * this results in a nice alphabetical ordering in the cpio file.
   *)
  (*let cmd = sprintf "ls -lR %s" rootdir in
  ignore (Sys.command cmd);*)
  let cmd =
    sprintf "(cd %s && cpio --quiet -o -0 -H newc) > %s"
      rootdir (tmpdir // "base.img") in
  let chan = open_process_out cmd in
  List.iter (fun (path, _, _) -> fprintf chan ".%s\000" path) baseimgfiles;
  let stat = close_process_out chan in
  (match stat with
   | WEXITED 0 -> ()
   | WEXITED i ->
       eprintf "febootstrap: command '%s' failed (returned %d), see earlier error messages\n" cmd i;
       exit i
   | WSIGNALED i ->
       eprintf "febootstrap: command '%s' killed by signal %d" cmd i;
       exit 1
   | WSTOPPED i ->
       eprintf "febootstrap: command '%s' stopped by signal %d" cmd i;
       exit 1
  );

  (* Undo directory permissions, because rm -rf can't delete files in
   * unreadable directories.
   *)
  List.iter (
    fun (path, { ft_dir = is_dir; ft_mode = mode }, _) ->
      if is_dir then chmod (rootdir // path) 0o755
  ) (List.rev baseimgfiles);

  (* Print warnings. *)
  if warnings then (
    (match !warn_unreadable with
     | [] -> ()
     | paths ->
         eprintf "febootstrap: warning: some host files are unreadable by non-root\n";
         eprintf "febootstrap: warning: get your distro to fix these files:\n";
         List.iter
           (fun path -> eprintf "\t%s\n%!" path)
           (List.sort compare paths)
    );
  );

  (* Near-atomically copy files to the final output directory. *)
  debug "writing %s ..." (outputdir // "base.img");
  let cmd =
    sprintf "mv %s %s"
      (Filename.quote (tmpdir // "base.img"))
      (Filename.quote (outputdir // "base.img")) in
  run_command cmd;
  debug "writing %s ..." (outputdir // "hostfiles");
  let cmd =
    sprintf "mv %s %s"
      (Filename.quote (tmpdir // "hostfiles"))
      (Filename.quote (outputdir // "hostfiles")) in
  run_command cmd
