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

(** Utilities. *)

val file_exists : string -> bool
  (** Return [true] iff file exists. *)

val dir_exists : string -> bool
  (** Return [true] iff dir exists. *)

val uniq : ?cmp:('a -> 'a -> int) -> 'a list -> 'a list
  (** Uniquify a list (the list must be sorted first). *)

val sort_uniq : ?cmp:('a -> 'a -> int) -> 'a list -> 'a list
  (** Sort and uniquify a list. *)

val input_all_lines : in_channel -> string list
  (** Input all lines from a channel, returning a list of lines. *)

val run_command_get_lines : string -> string list
  (** Run the command and read the list of lines that it prints to stdout. *)

val run_command : string -> unit
  (** Run a command using {!Sys.command} and exit if it fails.  Be careful
      when constructing the command to properly quote any arguments
      (using {!Filename.quote}). *)

val run_python : string -> string list -> unit
  (** [run_python code args] runs Python [code] with arguments [args].
      This does not return anything, but exits with an error message
      if the Python code returns an error. *)

val tmpdir : unit -> string
  (** [tmpdir ()] returns a newly created temporary directory.  The
      tmp directory is automatically removed when the program exits.
      Note that a fresh temporary directory is returned each time you
      call this function. *)

val (//) : string -> string -> string
  (** [x // y] concatenates file paths [x] and [y] into a single path. *)

val find : string -> string -> int
(** [find str sub] searches for [sub] in [str], returning the index
    or -1 if not found. *)

val string_split : string -> string -> string list
  (** [string_split sep str] splits [str] at [sep]. *)

val string_prefix : string -> string -> bool
  (** [string_prefix prefix str] returns true iff [str] starts with [prefix]. *)

val path_prefix : string -> string -> bool
  (** [path_prefix prefix path] returns true iff [path] is [prefix] or
      [path] starts with [prefix/]. *)

val filter_map : ('a -> 'b option) -> 'a list -> 'b list
  (** map + filter *)
