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
open Ext2fs
open Package_handler

(* The ext2 image that we build always has a fixed size, and we 'hope'
 * that the files fit in (otherwise we'll get an error).  Note that
 * the file is sparsely allocated.
 *
 * The downside of allocating a very large initial disk is that the
 * fixed overhead of ext2 is larger (since ext2 calculates it based on
 * the size of the disk).  For a 4GB disk the overhead is
 * approximately 66MB.
 *
 * In future, make this configurable, or determine it from the input
 * files (XXX).
 *)
let appliance_size = 4L *^ 1024L *^ 1024L *^ 1024L

let build_ext2 debug basedir files modpath kernel_version appliance =
  if debug >= 1 then
    printf "supermin: ext2: creating empty ext2 filesystem '%s'\n%!" appliance;

  let fd = openfile appliance [O_WRONLY;O_CREAT;O_TRUNC;O_NOCTTY] 0o644 in
  LargeFile.ftruncate fd appliance_size;
  close fd;

  let cmd =
    sprintf "%s %s ext2 -F%s %s"
      Config.mke2fs Config.mke2fs_t_option
      (if debug >= 2 then "" else "q")
      appliance in
  run_command cmd;

  let fs = ext2fs_open appliance in
  ext2fs_read_bitmaps fs;

  if debug >= 1 then
    printf "supermin: ext2: populating from base image\n%!";

  (* Read files from the base image, which has been unpacked into a
   * directory for us.
   *)
  ext2fs_copy_dir_recursively_from_host fs basedir "/";

  if debug >= 1 then
    printf "supermin: ext2: copying files from host filesystem\n%!";

  (* Copy files from host filesystem. *)
  List.iter (
    fun file ->
      let src = file_source file in
      ext2fs_copy_file_from_host fs src file.ft_path
  ) files;

  if debug >= 1 then
    printf "supermin: ext2: copying kernel modules\n%!";

  (* Import the kernel modules. *)
  ext2fs_copy_file_from_host fs "/lib" "/lib";
  ext2fs_copy_file_from_host fs "/lib/modules" "/lib/modules";
  ext2fs_copy_dir_recursively_from_host fs
    modpath ("/lib/modules/" ^ kernel_version);

  ext2fs_close fs
