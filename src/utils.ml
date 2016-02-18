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

let (+^) = Int64.add
let (-^) = Int64.sub
let ( *^ ) = Int64.mul
let (/^) = Int64.div

let (//) = Filename.concat
let quote = Filename.quote
let quoted_list names = String.concat " " (List.map quote names)

let dir_exists name =
  try (stat name).st_kind = S_DIR
  with Unix_error _ -> false

let uniq ?(cmp = Pervasives.compare) xs =
  let rec loop acc = function
    | [] -> acc
    | [x] -> x :: acc
    | x :: (y :: _ as xs) when cmp x y = 0 ->
       loop acc xs
    | x :: (y :: _ as xs) ->
       loop (x :: acc) xs
  in
  List.rev (loop [] xs)

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
       eprintf "supermin: command '%s' failed (returned %d), see earlier error messages\n" cmd i;
       exit i
   | WSIGNALED i ->
       eprintf "supermin: command '%s' killed by signal %d" cmd i;
       exit 1
   | WSTOPPED i ->
       eprintf "supermin: command '%s' stopped by signal %d" cmd i;
       exit 1
  );
  lines

let run_command cmd =
  if Sys.command cmd <> 0 then (
    eprintf "supermin: %s: command failed, see earlier errors\n" cmd;
    exit 1
  )

let run_shell code args =
  let cmd = sprintf "sh -c %s arg0 %s"
    (Filename.quote code)
    (String.concat " " (List.map Filename.quote args)) in
  if Sys.command cmd <> 0 then (
    eprintf "supermin: external shell program failed, see earlier error messages\n";
    exit 1
  )

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

let string_random8 =
  let chars = "abcdefghijklmnopqrstuvwxyz0123456789" in
  fun () ->
    String.concat "" (
      List.map (
        fun _ ->
          let c = Random.int 36 in
          let c = chars.[c] in
          String.make 1 c
      ) [1;2;3;4;5;6;7;8]
    )

let rec filter_map f = function
  | [] -> []
  | x :: xs ->
      let x = f x in
      match x with
      | None -> filter_map f xs
      | Some x -> x :: filter_map f xs

let rex_numbers = Str.regexp "^\\([0-9]+\\)\\(.*\\)$"
let rex_letters = Str.regexp_case_fold "^\\([a-z]+\\)\\(.*\\)$"

let rec compare_version v1 v2 =
  compare (split_version v1) (split_version v2)

and split_version = function
  | "" -> []
  | str ->
    let first, rest =
      if Str.string_match rex_numbers str 0 then (
        let n = Str.matched_group 1 str in
        let rest = Str.matched_group 2 str in
        let n =
          try `Number (int_of_string n)
          with Failure "int_of_string" -> `String n in
        n, rest
      )
      else if Str.string_match rex_letters str 0 then
        `String (Str.matched_group 1 str), Str.matched_group 2 str
      else (
        let len = String.length str in
        `Char str.[0], String.sub str 1 (len-1)
      ) in
    first :: split_version rest

let compare_architecture a1 a2 =
  let index_of_architecture = function
    | "noarch" | "all" -> 100
    | "i386" | "i486" | "i586" | "i686" | "x86_32" | "x86-32" -> 32
    | "x86_64" | "x86-64" | "amd64" -> 64
    | "armel" | "armhf" -> 32
    | "aarch64" -> 64
    | a when string_prefix "armv5" a -> 32
    | a when string_prefix "armv6" a -> 32
    | a when string_prefix "armv7" a -> 32
    | a when string_prefix "armv8" a -> 64
    | "ppc" | "ppc32" -> 32
    | a when string_prefix "ppc64" a -> 64
    | "sparc" | "sparc32" -> 32
    | "sparc64" -> 64
    | "ia64" -> 64
    | "s390" -> 32
    | "s390x" -> 64
    | "alpha" -> 64
    | a ->
      eprintf "supermin: missing support for architecture '%s'\nIt may need to be added to supermin.\n" a;
      exit 1
  in
  compare (index_of_architecture a1) (index_of_architecture a2)

(* Parse a size field, eg. "10G". *)
let parse_size =
  let const_re = Str.regexp "^\\([.0-9]+\\)\\([bKMG]\\)$" in
  fun field ->
    let matches rex = Str.string_match rex field 0 in
    let sub i = Str.matched_group i field in
    let size_scaled f = function
      | "b" -> Int64.of_float f
      | "K" -> Int64.of_float (f *. 1024.)
      | "M" -> Int64.of_float (f *. 1024. *. 1024.)
      | "G" -> Int64.of_float (f *. 1024. *. 1024. *. 1024.)
      | _ -> assert false
    in

    if matches const_re then (
      size_scaled (float_of_string (sub 1)) (sub 2)
    ) else (
      eprintf "supermin: cannot parse size field '%s'\n" field;
      exit 1
    )
