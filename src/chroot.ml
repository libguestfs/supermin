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

let build_chroot debug files outputdir =
  List.iter (
    fun file ->
      try
        let path = file.ft_source_path in
        let st = lstat path in
        let opath = outputdir // file.ft_path in
        match st.st_kind with
        | S_DIR ->
          (* Note we fix up the permissions of directories in a second
           * pass, otherwise we risk creating a directory that we are
           * unable to write inside.  GNU tar does the same thing!
           *)
          if debug >= 2 then printf "supermin: chroot: mkdir %s\n%!" opath;
          mkdir opath 0o700

        | S_LNK ->
          let link = readlink path in
          (* Need to turn absolute links into relative links, so they
           * always work, whether or not you are in a chroot.
           *)
          let link =
            if String.length link < 1 || link.[0] <> '/' then
              link
            else (
              let link = ref link in
              for i = 1 to String.length path - 1 do
                if path.[i] = '/' then link := "../" ^ !link
              done;
              !link
            ) in

          if debug >= 2 then
            printf "supermin: chroot: link %s -> %s\n%!" opath link;
          symlink link opath

        | S_REG | S_CHR | S_BLK | S_FIFO | S_SOCK ->
          if debug >= 2 then printf "supermin: chroot: copy %s\n%!" opath;
          let cmd = sprintf "cp -p %s %s" path opath in
          ignore (Sys.command cmd)
      with Unix_error _ -> ()
  ) files;

  (* Second pass: fix up directory permissions in reverse. *)
  let dirs = filter_map (
    fun file ->
      let st = lstat file.ft_source_path in
      if st.st_kind = S_DIR then Some (file.ft_path, st) else None
  ) files in
  List.iter (
    fun (path, st) ->
      let opath = outputdir // path in
      (try chown opath st.st_uid st.st_gid with Unix_error _ -> ());
      (try chmod opath st.st_perm with Unix_error _ -> ())
  ) (List.rev dirs)
