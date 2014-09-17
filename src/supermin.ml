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

open Types
open Utils
open Prepare
open Build
open Package_handler

type mode = Prepare | Build

let usage_msg = "\
supermin - tool for creating supermin appliances
Copyright (C) 2009-2014 Red Hat Inc.

Usage:

  supermin --prepare LIST OF PACKAGES ...
  supermin --build INPUT [INPUT ...]

For full instructions, read the supermin(1) man page.

Options:
"

let main () =
  Random.self_init ();

  (* Make sure that all the subcommands that we run are printing
   * messages in English.  Certain package handlers (cough RPM) rely on
   * this.
   *)
  putenv "LANG" "C";

  (* Create a temporary directory for scratch storage. *)
  let tmpdir =
    let tmpdir = Filename.temp_file "supermin" ".tmpdir" in
    unlink tmpdir;
    mkdir tmpdir 0o700;
    at_exit
      (fun () ->
        let cmd = sprintf "rm -rf %s" (quote tmpdir) in
        ignore (Sys.command cmd));
    tmpdir in

  let debug, mode, if_newer, inputs, lockfile, outputdir, args =
    let display_version () =
      printf "supermin %s\n" Config.package_version;
      exit 0
    in

    let display_drivers () =
      list_package_handlers ();
      exit 0
    in

    let add xs s = xs := s :: !xs in

    let copy_kernel = ref false in
    let debug = ref 0 in
    let dtb_wildcard = ref "" in
    let format = ref None in
    let host_cpu = ref Config.host_cpu in
    let if_newer = ref false in
    let lockfile = ref "" in
    let mode = ref None in
    let outputdir = ref "" in
    let packager_config = ref "" in
    let use_installed = ref false in

    let set_debug () = incr debug in

    let set_format = function
      | "chroot" | "fs" | "filesystem" -> format := Some Chroot
      | "ext2" -> format := Some Ext2
      | s ->
        eprintf "supermin: unknown --format option (%s)\n" s;
        exit 1
    in

    let rec set_prepare_mode () =
      if !mode <> None then
        bad_mode ();
      mode := Some Prepare
    and set_build_mode () =
      if !mode <> None then
        bad_mode ();
      mode := Some Build
    and bad_mode () =
      eprintf "supermin: you must use --prepare or --build to select the mode\n";
      exit 1
    in

    let error_supermin_5 () =
      eprintf "supermin: *** error: This is supermin version 5.\n";
      eprintf "supermin: *** It looks like you are looking for supermin version 4.\n";
      eprintf "\n";
      eprintf "This version of supermin will not work.  You need to find the old version\n";
      eprintf "or upgrade to libguestfs >= 1.26.\n";
      eprintf "\n";
      exit 1
    in

    let ditto = " -\"-" in
    let argspec = Arg.align [
      "--build",   Arg.Unit set_build_mode,   " Build a full appliance";
      "--copy-kernel", Arg.Set copy_kernel,   " Copy kernel instead of symlinking";
      "--dtb",     Arg.Set_string dtb_wildcard, "WILDCARD Find device tree matching wildcard";
      "-f",        Arg.String set_format,     "chroot|ext2 Set output format";
      "--format",  Arg.String set_format,     ditto;
      "--host-cpu", Arg.Set_string host_cpu,  "ARCH Set host CPU architecture";
      "--if-newer", Arg.Set if_newer,             " Only build if needed";
      "--list-drivers", Arg.Unit display_drivers, " Display list of drivers and exit";
      "--lock",    Arg.Set_string lockfile,   "LOCKFILE Use a lock file";
      "--names",   Arg.Unit error_supermin_5, " Give an error for people needing supermin 4";
      "-o",        Arg.Set_string outputdir,  "OUTPUTDIR Set output directory";
      "--packager-config", Arg.Set_string packager_config, "CONFIGFILE Set packager config file";
      "--prepare", Arg.Unit set_prepare_mode, " Prepare a supermin appliance";
      "--use-installed", Arg.Set use_installed, " Use installed files instead of accessing network";
      "-v",        Arg.Unit set_debug,        " Enable debugging messages";
      "--verbose", Arg.Unit set_debug,        ditto;
      "-V",        Arg.Unit display_version,  " Display version and exit";
      "--version", Arg.Unit display_version,  ditto;
    ] in
    let inputs = ref [] in
    let anon_fun = add inputs in
    Arg.parse argspec anon_fun usage_msg;

    let copy_kernel = !copy_kernel in
    let debug = !debug in
    let dtb_wildcard = match !dtb_wildcard with "" -> None | s -> Some s in
    let host_cpu = !host_cpu in
    let if_newer = !if_newer in
    let inputs = List.rev !inputs in
    let lockfile = match !lockfile with "" -> None | s -> Some s in
    let mode = match !mode with Some x -> x | None -> bad_mode (); Prepare in
    let outputdir = !outputdir in
    let packager_config =
      match !packager_config with "" -> None | s -> Some s in
    let use_installed = !use_installed in

    let format =
      match mode, !format with
      | Prepare, Some _ ->
        eprintf "supermin: cannot use --prepare and --format options together\n";
        exit 1
      | Prepare, None -> Chroot (* doesn't matter, prepare doesn't use this *)
      | Build, None ->
        eprintf "supermin: when using --build, you must specify an output --format\n";
        exit 1
      | Build, Some f -> f in

    if outputdir = "" then (
      eprintf "supermin: output directory (-o option) must be supplied\n";
      exit 1
    );

    debug, mode, if_newer, inputs, lockfile, outputdir,
    (copy_kernel, dtb_wildcard, format, host_cpu,
     packager_config, tmpdir, use_installed) in

  if debug >= 1 then printf "supermin: version: %s\n" Config.package_version;

  (* Try to find out which package management system we're using.
   * This fails with an error if one could not be located.
   *)
  let () =
    let (_, _, _, _, packager_config, tmpdir, _) = args in
    let settings = {
      debug = debug;
      tmpdir = tmpdir;
      packager_config = packager_config;
    } in
    check_system settings in

  if debug >= 1 then
    printf "supermin: package handler: %s\n" (get_package_handler_name ());

  (* Grab the lock file, is using.  Note it is released automatically
   * when the program exits for any reason.
   *)
  (match lockfile with
  | None -> ()
  | Some lockfile ->
    if debug >= 1 then printf "supermin: acquiring lock on %s\n%!" lockfile;
    let fd = openfile lockfile [O_WRONLY;O_CREAT] 0o644 in
    lockf fd F_LOCK 0;
  );

  (* If the --if-newer flag was given, check the dates on input files,
   * package database and output directory.  If the output directory
   * does not exist, or if the dates of either input files or package
   * database is newer, then we rebuild.  Else we can just exit.
   *)
  if if_newer then (
    try
      let odate = (lstat outputdir).st_mtime in
      let idates = List.map (fun d -> (lstat d).st_mtime) inputs in
      let pdate = (get_package_handler ()).ph_get_package_database_mtime () in
      if List.for_all (fun idate -> idate < odate) (pdate :: idates) then (
        if debug >= 1 then
          printf "supermin: if-newer: output does not need rebuilding\n%!";
        exit 0
      )
    with
      Unix_error _ -> () (* just continue *)
  );

  (* Create the output directory nearly atomically. *)
  let new_outputdir = outputdir ^ "." ^ string_random8 () in
  mkdir new_outputdir 0o755;
  at_exit
    (fun () ->
      let cmd =
        sprintf "rm -rf %s 2>/dev/null" (quote new_outputdir) in
      ignore (Sys.command cmd));

  (match mode with
  | Prepare -> prepare debug args inputs new_outputdir
  | Build -> build debug args inputs new_outputdir
  );

  (* Delete the old output directory if it exists. *)
  let old_outputdir =
    try
      let old_outputdir = outputdir ^ "." ^ string_random8 () in
      rename outputdir old_outputdir;
      Some old_outputdir
    with
      Unix_error _ -> None in

  if debug >= 1 then
    printf "supermin: renaming %s to %s\n%!" new_outputdir outputdir;
  rename new_outputdir outputdir;

  match old_outputdir with
  | None -> ()
  | Some old_outputdir ->
    let cmd =
      (* We have to do the chmod since unwritable directories cannot
       * be deleted by 'rm -rf'.  Unwritable directories can be created
       * by '-f chroot'.
       *)
      sprintf "( chmod -R +w %s ; rm -rf %s ) 2>/dev/null &"
        (quote old_outputdir) (quote old_outputdir) in
    ignore (Sys.command cmd);

  package_handler_shutdown ()

let () =
  try main ()
  with
  | Unix.Unix_error (code, fname, "") -> (* from a syscall *)
    eprintf "supermin: error: %s: %s\n" fname (Unix.error_message code);
    exit 1
  | Unix.Unix_error (code, fname, param) -> (* from a syscall *)
    eprintf "supermin: error: %s: %s: %s\n" fname (Unix.error_message code)
      param;
    exit 1
  | Failure msg ->                      (* from failwith/failwithf *)
    eprintf "supermin: failure: %s\n" msg;
    exit 1
  | Invalid_argument msg ->             (* probably should never happen *)
    eprintf "supermin: internal error: invalid argument: %s\n" msg;
    exit 1
  | Assert_failure (file, line, char) -> (* should never happen *)
    eprintf "supermin: internal error: assertion failed at %s, line %d, char %d\n" file line char;
    exit 1
  | Not_found ->                        (* should never happen *)
    eprintf "supermin: internal error: Not_found exception was thrown\n";
    exit 1
  | exn ->                              (* something not matched above *)
    eprintf "supermin: exception: %s\n" (Printexc.to_string exn);
    exit 1
