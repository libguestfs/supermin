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
open Glob

let rec build_kernel debug host_cpu copy_kernel kernel =
  (* Locate the kernel.
   * SUPERMIN_* environment variables override everything.  If those
   * are not present then we look in /lib/modules and /boot.
   *)
  let kernel_file, kernel_name, kernel_version, modpath =
    if debug >= 1 then
      printf "supermin: kernel: looking for kernel using environment variables ...\n%!";
    match find_kernel_from_env_vars debug with
    | Some k -> k
    | None ->
       if debug >= 1 then
         printf "supermin: kernel: looking for kernels in /lib/modules/*/vmlinuz ...\n%!";
       match find_kernel_from_lib_modules debug with
       | Some k -> k
       | None ->
          if debug >= 1 then
            printf "supermin: kernel: looking for kernels in /boot ...\n%!";
          match find_kernel_from_boot debug host_cpu with
          | Some k -> k
          | None ->
             error_no_kernels host_cpu in

  if debug >= 1 then (
    printf "supermin: kernel: picked vmlinuz %s\n%!" kernel_file;
    printf "supermin: kernel: kernel_version %s\n" kernel_version;
    printf "supermin: kernel: modpath %s\n%!" modpath;
  );

  copy_or_symlink_file copy_kernel kernel_file kernel;

  (kernel_version, modpath)

and error_no_kernels host_cpu =
  error "\
failed to find a suitable kernel (host_cpu=%s).

I looked for kernels in /boot and modules in /lib/modules.

If this is a Xen guest, and you only have Xen domU kernels
installed, try installing a fullvirt kernel (only for
supermin use, you shouldn't boot the Xen guest with it)."
    host_cpu

and find_kernel_from_env_vars debug  =
  try
    let kernel_env = getenv "SUPERMIN_KERNEL" in
    if debug >= 1 then
      printf "supermin: kernel: SUPERMIN_KERNEL=%s\n%!" kernel_env;
    let kernel_version =
      try
        let v = getenv "SUPERMIN_KERNEL_VERSION" in
        if debug >= 1 then
          printf "supermin: kernel: SUPERMIN_KERNEL_VERSION=%s\n%!" v;
        v
      with Not_found -> get_kernel_version_from_file kernel_env in
    let kernel_name = Filename.basename kernel_env in
    let modpath = find_modpath debug kernel_version in
    Some (kernel_env, kernel_name, kernel_version, modpath)
  with Not_found -> None

and find_kernel_from_lib_modules debug =
  let kernels =
    let files = glob "/lib/modules/*/vmlinuz" [GLOB_NOSORT; GLOB_NOESCAPE] in
    let files = Array.to_list files in
    let kernels =
      List.map (
        fun f ->
          let modpath = Filename.dirname f in
          f, Filename.basename f, Filename.basename modpath, modpath
      ) files in
    List.sort (
      fun (_, _, a, _) (_, _, b, _) -> compare_version b a
    ) kernels in

  match kernels with
  | kernel :: _ -> Some kernel
  | [] -> None

and find_kernel_from_boot debug host_cpu =
  let is_arm =
    String.length host_cpu >= 3 &&
    host_cpu.[0] = 'a' && host_cpu.[1] = 'r' && host_cpu.[2] = 'm' in

  let all_files = Sys.readdir "/boot" in
  let all_files = Array.to_list all_files in

  (* In original: ls -1dvr /boot/vmlinuz-*.$arch* 2>/dev/null | grep -v xen *)
  let patterns = patt_of_cpu host_cpu in
  let files = kernel_filter patterns is_arm all_files in

  let files =
    if files <> [] then files
    else
      (* In original: ls -1dvr /boot/vmlinuz-* 2>/dev/null | grep -v xen *)
      kernel_filter ["vmlinu?-*"] is_arm all_files in

  let files = List.sort (fun a b -> compare_version b a) files in
  let kernels =
    List.map (
      fun kernel_name ->
        let kernel_version = get_kernel_version kernel_name in
        let kernel_file = "/boot" // kernel_name in
        let modpath = find_modpath debug kernel_version in
        (kernel_file, kernel_name, kernel_version, modpath)
    ) files in

  let kernels =
    List.filter (fun (_, kernel_name, _, _) -> has_modpath kernel_name) kernels in

  match kernels with
  | kernel :: _ -> Some kernel
  | [] -> None

and kernel_filter patterns is_arm all_files =
  let files =
    List.filter
      (fun filename ->
        List.exists
          (fun patt -> fnmatch patt filename [FNM_NOESCAPE]) patterns
      ) all_files in
  let files =
    List.filter (fun filename -> find filename "xen" = -1) files in
  let files =
    if not is_arm then files
    else (
      List.filter (fun filename ->
	find filename "tegra" = -1
      ) files
    ) in
  files

and patt_of_cpu host_cpu =
  let models =
    match host_cpu with
    | "mips" | "mips64" -> [host_cpu; "*-malta"]
    | "ppc" | "powerpc" | "powerpc64" -> ["ppc"; "powerpc"; "powerpc64"]
    | "sparc" | "sparc64" -> ["sparc"; "sparc64"]
    | "amd64" | "x86_64" -> ["amd64"; "x86_64"]
    | "parisc" | "parisc64" -> ["hppa"; "hppa64"]
    | "ppc64el" -> ["powerpc64le"]
    | _ when host_cpu.[0] = 'i' && host_cpu.[2] = '8' && host_cpu.[3] = '6' -> ["?86"]
    | _ when String.length host_cpu >= 5 && String.sub host_cpu 0 5 = "armv7" ->  ["armmp"]
    | _ -> [host_cpu]
  in
  List.map (fun model -> sprintf "vmlinu?-*-%s" model) models

and find_modpath debug kernel_version =
  try
    let modpath = getenv "SUPERMIN_MODULES" in
    if debug >= 1 then
      printf "supermin: kernel: SUPERMIN_MODULES=%s\n%!" modpath;
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
  if (string_prefix "vmlinuz-" kernel_name) ||
    (string_prefix "vmlinux-" kernel_name) then (
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
