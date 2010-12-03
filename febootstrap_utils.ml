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

let (//) = Filename.concat

let file_exists name =
  try access name [F_OK]; true
  with Unix_error _ -> false

let dir_exists name =
  try (stat name).st_kind = S_DIR
  with Unix_error _ -> false

let rec uniq ?(cmp = Pervasives.compare) = function
  | [] -> []
  | [x] -> [x]
  | x :: y :: xs when cmp x y = 0 ->
      uniq ~cmp (x :: xs)
  | x :: y :: xs ->
      x :: uniq ~cmp (y :: xs)

let sort_uniq ?(cmp = Pervasives.compare) xs =
  let xs = List.sort cmp xs in
  let xs = uniq ~cmp xs in
  xs

let rec input_all_lines chan =
  try let line = input_line chan in line :: input_all_lines chan
  with End_of_file -> []

let run_command_get_lines cmd =
  let chan = open_process_in cmd in
  let lines = input_all_lines chan in
  let stat = close_process_in chan in
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
  lines

let run_command cmd =
  if Sys.command cmd <> 0 then (
    eprintf "febootstrap: %s: command failed, see earlier errors\n" cmd;
    exit 1
  )

let run_python code args =
  let cmd = sprintf "python -c %s %s"
    (Filename.quote code)
    (String.concat " " (List.map Filename.quote args)) in
  if Sys.command cmd <> 0 then (
    eprintf "febootstrap: external python program failed, see earlier error messages\n";
    exit 1
  )

let tmpdir () =
  let chan = open_in "/dev/urandom" in
  let data = String.create 16 in
  really_input chan data 0 (String.length data);
  close_in chan;
  let data = Digest.to_hex (Digest.string data) in
  (* Note this is secure, because if the name already exists, even as a
   * symlink, mkdir(2) will fail.
   *)
  let tmpdir = Filename.temp_dir_name // sprintf "febootstrap%s.tmp" data in
  Unix.mkdir tmpdir 0o700;
  at_exit
    (fun () ->
       let cmd = sprintf "rm -rf %s" (Filename.quote tmpdir) in
       ignore (Sys.command cmd));
  tmpdir

let rec find s sub =
  let len = String.length s in
  let sublen = String.length sub in
  let rec loop i =
    if i <= len-sublen then (
      let rec loop2 j =
        if j < sublen then (
          if s.[i+j] = sub.[j] then loop2 (j+1)
          else -1
        ) else
          i (* found *)
      in
      let r = loop2 0 in
      if r = -1 then loop (i+1) else r
    ) else
      -1 (* not found *)
  in
  loop 0

let rec string_split sep str =
  let len = String.length str in
  let seplen = String.length sep in
  let i = find str sep in
  if i = -1 then [str]
  else (
    let s' = String.sub str 0 i in
    let s'' = String.sub str (i+seplen) (len-i-seplen) in
    s' :: string_split sep s''
  )

let string_prefix p str =
  let len = String.length str in
  let plen = String.length p in
  len >= plen && String.sub str 0 plen = p

let path_prefix p path =
  let len = String.length path in
  let plen = String.length p in
  path = p || (len > plen && String.sub path 0 (plen+1) = (p ^ "/"))

let rec filter_map f = function
  | [] -> []
  | x :: xs ->
      let x = f x in
      match x with
      | None -> filter_map f xs
      | Some x -> x :: filter_map f xs
