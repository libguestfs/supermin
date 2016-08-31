(* supermin 5
 * Copyright (C) 2016 Red Hat Inc.
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

open Utils

let split sep str =
  let len = String.length sep in
  let seplen = String.length str in
  let i = find str sep in
  if i = -1 then str, ""
  else (
    String.sub str 0 i, String.sub str (i + len) (seplen - i - len)
  )

type os_release = {
  id : string;
}

let data = ref None
let parsed = ref false

let rec get_data () =
  if !parsed = false then (
    data := parse ();
    parsed := true;
  );

  !data

and parse () =
  let file = "/etc/os-release" in
  if Sys.file_exists file then (
    let chan = open_in file in
    let lines = input_all_lines chan in
    close_in chan;
    let lines = List.filter ((<>) "") lines in
    let lines = List.filter (fun s -> s.[0] <> '#') lines in

    let id = ref "" in

    List.iter (
      fun line ->
        let field, value = split "=" line in
        let value =
          let len = String.length value in
          if len > 1 &&
             ((value.[0] = '"' && value.[len-1] = '"') ||
              (value.[0] = '\'' && value.[len-1] = '\'')) then
            String.sub value 1 (len - 2)
          else value in
        match field with
        | "ID" -> id := value
        | _ -> ()
    ) lines;

    Some { id = !id; }
  ) else
    None

let get_id () =
  match get_data () with
  | None -> ""
  | Some d -> d.id
