#!/usr/bin/ocamlrun ocaml

(* Copyright (C) 2010-2014 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Printf
#load "str.cma"

let (//) = Filename.concat

let read_whole_file path =
  let buf = Buffer.create 16384 in
  let chan = open_in path in
  let maxlen = 16384 in
  let s = String.create maxlen in
  let rec loop () =
    let r = input chan s 0 maxlen in
    if r > 0 then (
      Buffer.add_substring buf s 0 r;
      loop ()
    )
  in
  loop ();
  close_in chan;
  Buffer.contents buf

let string_charsplit sep =
  Str.split (Str.regexp_string sep)

let find_trs basedir =
  let rec internal_find_trs basedir =
    let items = Array.to_list (Sys.readdir basedir) in
    let items = List.map (fun x -> basedir // x) items in
    let dirs, files = List.partition (
      fun x ->
        try Sys.is_directory x
        with Sys_error _ -> false
    ) items in
    let files = List.filter (fun x -> Filename.check_suffix x ".trs") files in
    let subdirs_files = List.fold_left (
      fun acc dir ->
        (internal_find_trs dir) :: acc
    ) [] dirs in
    let subdirs_files = List.rev subdirs_files in
    List.concat (files :: subdirs_files)
  in
  internal_find_trs basedir

let iterate_results trs_files =
  let total = ref 0 in
  let failures = ref 0 in
  let errors = ref 0 in
  let skipped = ref 0 in
  let buf = Buffer.create 16384 in
  List.iter (
    fun file ->
      let rec results file =
        let content = read_whole_file file in
        let lines = string_charsplit "\n" content in
        let log = get_log file in
        let testname = name_for_test file in
        List.iter (
          fun line ->
            let line = string_charsplit " " line in
            (match line with
            | ":test-result:" :: result :: rest ->
              let name = String.concat " " rest in
              let name = if String.length name > 0 then name else testname in
              let print_tag_with_log tag =
                Buffer.add_string buf (sprintf "  <testcase name=\"%s\">\n" name);
                Buffer.add_string buf (sprintf "    <%s><![CDATA[%s]]></%s>\n" tag log tag);
                Buffer.add_string buf (sprintf "  </testcase>\n")
              in
              (match result with
              | "PASS" ->
                print_tag_with_log "system-out"
              | "SKIP" ->
                skipped := !skipped + 1;
                print_tag_with_log "skipped"
              | "XFAIL" | "FAIL" | "XPASS" ->
                failures := !failures + 1;
                print_tag_with_log "error"
              | "ERROR" | _ ->
                errors := !errors + 1;
                print_tag_with_log "error"
              );
              total := !total + 1
            | _ -> ()
            );
        ) lines;
      and name_for_test filename =
        Filename.chop_suffix (Filename.basename filename) ".trs"
      and get_log filename =
        let log_filename = (Filename.chop_suffix filename ".trs") ^ ".log" in
        try read_whole_file log_filename with _ -> ""
      in
      results file
  ) trs_files;
  Buffer.contents buf, !total, !failures, !errors, !skipped

let () =
  if Array.length Sys.argv < 3 then (
    printf "%s PROJECTNAME BASEDIR\n" Sys.argv.(0);
    exit 1
  );
  let name = Sys.argv.(1) in
  let basedir = Sys.argv.(2) in
  let trs_files = List.sort compare (find_trs basedir) in
  let buf, total, failures, errors, skipped =
    iterate_results trs_files in
  printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<testsuite name=\"%s\" tests=\"%d\" failures=\"%d\" skipped=\"%d\" errors=\"%d\">
%s</testsuite>
" name total failures skipped errors buf
