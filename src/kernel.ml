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
open Fnmatch

let rec build_kernel debug host_cpu dtb_wildcard copy_kernel kernel dtb =
  (* Locate the kernel. *)
  let kernel_name, kernel_version =
    find_kernel debug host_cpu copy_kernel kernel in

  (* If the user passed --dtb option, locate dtb. *)
  (match dtb_wildcard with
  | None -> ()
  | Some wildcard ->
    find_dtb debug copy_kernel kernel_name wildcard dtb
  );

  (* Get the kernel modules. *)
  let modpath = find_modpath debug kernel_version in

  if debug >= 1 then (
    printf "supermin: kernel: kernel_version %s\n" kernel_version;
    printf "supermin: kernel: modules %s\n%!" modpath;
  );

  (kernel_version, modpath)

and find_kernel debug host_cpu copy_kernel kernel =
  let kernel_file, kernel_name, kernel_version =
    try
      let kernel_env = getenv "SUPERMIN_KERNEL" in
      if debug >= 1 then
        printf "supermin: kernel: SUPERMIN_KERNEL environment variable %s\n%!"
          kernel_env;
      let kernel_version = get_kernel_version_from_file kernel_env in
      if debug >= 1 then
        printf "supermin: kernel: SUPERMIN_KERNEL version %s\n%!"
          kernel_version;
      let kernel_name = Filename.basename kernel_env in
      kernel_env, kernel_name, kernel_version
    with Not_found ->
      let is_x86 =
        String.length host_cpu = 4 &&
        host_cpu.[0] = 'i' && host_cpu.[2] = '8' && host_cpu.[3] = '6' in
      let is_arm =
        String.length host_cpu >= 3 &&
        host_cpu.[0] = 'a' && host_cpu.[1] = 'r' && host_cpu.[2] = 'm' in

      let all_files = Sys.readdir "/boot" in
      let all_files = Array.to_list all_files in

      (* In original: ls -1dvr /boot/vmlinuz-*.$arch* 2>/dev/null | grep -v xen *)
      let patt =
        if is_x86 then "vmlinuz-*.i?86*"
        else "vmlinuz-*." ^ host_cpu ^ "*" in
      let files = kernel_filter patt is_arm all_files in

      let files =
        if files <> [] then files
        else
          (* In original: ls -1dvr /boot/vmlinuz-* 2>/dev/null | grep -v xen *)
          kernel_filter "vmlinuz-*" is_arm all_files in

      if files = [] then no_kernels ();

      let files = List.sort (fun a b -> compare_version b a) files in
      let kernel_name = List.hd files in
      let kernel_version = get_kernel_version kernel_name in

      if debug >= 1 then
        printf "supermin: kernel: picked kernel %s\n%!" kernel_name;

      ("/boot" // kernel_name), kernel_name, kernel_version in

  copy_or_symlink_file copy_kernel kernel_file kernel;
  kernel_name, kernel_version

and kernel_filter patt is_arm all_files =
  let files =
    List.filter
      (fun filename -> fnmatch patt filename [FNM_NOESCAPE]) all_files in
  let files =
    List.filter (fun filename -> find filename "xen" = -1) files in
  let files =
    if not is_arm then files
    else (
      List.filter (fun filename ->
        find filename "lpae" = -1 && find filename "tegra" = -1
      ) files
    ) in
  List.filter (fun filename -> has_modpath filename) files

and no_kernels () =
  eprintf "\
supermin: failed to find a suitable kernel.

I looked for kernels in /boot and modules in /lib/modules.

If this is a Xen guest, and you only have Xen domU kernels
installed, try installing a fullvirt kernel (only for
supermin use, you shouldn't boot the Xen guest with it).\n";
  exit 1

and find_dtb debug copy_kernel kernel_name wildcard dtb =
  let dtb_file =
    try
      let dtb_file = getenv "SUPERMIN_DTB" in
      if debug >= 1 then
        printf "supermin: kernel: SUPERMIN_DTB environment variable = %s\n%!"
          dtb_file;
      dtb_file
    with Not_found ->
      (* Replace vmlinuz- with dtb- *)
      if not (string_prefix "vmlinuz-" kernel_name) then
        no_dtb_dir kernel_name;
      let dtb_dir =
        "/boot/dtb-" ^
          String.sub kernel_name 8 (String.length kernel_name - 8) in
      if not (dir_exists dtb_dir) then
        no_dtb_dir kernel_name;

      let all_files = Sys.readdir dtb_dir in
      let all_files = Array.to_list all_files in

      let files =
        List.filter (fun filename -> fnmatch wildcard filename [FNM_NOESCAPE])
          all_files in
      if files = [] then
        no_dtb dtb_dir wildcard;

      let dtb_name = List.hd files in
      let dtb_file = dtb_dir // dtb_name in
      if debug >= 1 then
        printf "supermin: kernel: picked dtb %s\n%!" dtb_file;
      dtb_file in

  copy_or_symlink_file copy_kernel dtb_file dtb

and no_dtb_dir kernel_name =
  eprintf "\
supermin: failed to find a dtb (device tree) directory.

I expected to take '%s' and to
replace vmlinuz- with dtb- to form a directory.

You can set SUPERMIN_KERNEL, SUPERMIN_MODULES and SUPERMIN_DTB
to override automatic selection.  See supermin(1).\n"
    kernel_name;
  exit 1

and no_dtb dtb_dir wildcard =
  eprintf "\
supermin: failed to find a matching device tree.

I looked for a file matching '%s' in directory '%s'.

You can set SUPERMIN_KERNEL, SUPERMIN_MODULES and SUPERMIN_DTB
to override automatic selection.  See supermin(1).\n"
    wildcard dtb_dir;
  exit 1

and find_modpath debug kernel_version =
  try
    let modpath = getenv "SUPERMIN_MODULES" in
    if debug >= 1 then
      printf "supermin: kernel: SUPERMIN_MODULES environment variable = %s\n%!"
        modpath;
    modpath
  with Not_found ->
    let modpath = "/lib/modules/" ^ kernel_version in
    if debug >= 1 then
      printf "supermin: kernel: picked modules path %s\n%!" modpath;
    modpath

and has_modpath kernel_name =
  try
    let kv = get_kernel_version kernel_name in
    modules_dep_exists kv
  with
  | Not_found -> false

and get_kernel_version kernel_name =
  if string_prefix "vmlinuz-" kernel_name then (
    let kv = String.sub kernel_name 8 (String.length kernel_name - 8) in
    if modules_dep_exists kv then kv
    else get_kernel_version_from_name kernel_name
  ) else get_kernel_version_from_name kernel_name

and modules_dep_exists kv =
  try (lstat ("/lib/modules/" ^ kv ^ "/modules.dep")).st_kind = S_REG
  with Unix_error _ -> false

and get_kernel_version_from_name kernel_name =
  get_kernel_version_from_file ("/boot" // kernel_name)

(* Extract the kernel version from a Linux kernel file.
 *
 * Returns a string containing the version or [Not_found] if the
 * file can't be read, is not a Linux kernel, or the version can't
 * be found.
 *
 * See ftp://ftp.astron.com/pub/file/file-<ver>.tar.gz
 * (file-<ver>/magic/Magdir/linux) for the rules used to find the
 * version number:
 *   514             string  HdrS     Linux kernel
 *   >518            leshort >0x1ff
 *   >>(526.s+0x200) string  >\0      version %s,
 *
 * Bugs: probably limited to x86 kernels.
 *)
and get_kernel_version_from_file file =
  try
    let chan = open_in file in
    let buf = read_string chan 514 4 in
    if buf <> "HdrS" then (
      close_in chan;
      raise Not_found
    );
    let s = read_leshort chan 518 in
    if s < 0x1ff then (
      close_in chan;
      raise Not_found
    );
    let offset = read_leshort chan 526 in
    if offset < 0 then (
      close_in chan;
      raise Not_found
    );
    let buf = read_string chan (offset + 0x200) 132 in
    close_in chan;
    let rec loop i =
      if i < 132 then (
        if buf.[i] = '\000' || buf.[i] = ' ' ||
          buf.[i] = '\t' || buf.[i] = '\n' then
          String.sub buf 0 i
        else
          loop (i+1)
      )
      else raise Not_found
    in
    loop 0
  with
  | Sys_error _ -> raise Not_found
  | Invalid_argument _ -> raise Not_found

(* Read an unsigned little endian short at a specified offset in a file. *)
and read_leshort chan offset =
  let buf = read_string chan offset 2 in
  (Char.code buf.[1] lsl 8) lor Char.code buf.[0]

and read_string chan offset len =
  seek_in chan offset;
  let buf = String.create len in
  really_input chan buf 0 len;
  buf

and copy_or_symlink_file copy_kernel src dest =
  if not copy_kernel then
    symlink src dest
  else (
    let cmd = sprintf "cp -p %s %s" (quote src) (quote dest) in
    run_command cmd
  )
