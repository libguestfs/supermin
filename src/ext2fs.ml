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

type t

external ext2fs_open : string -> t = "supermin_ext2fs_open"
external ext2fs_close : t -> unit = "supermin_ext2fs_close"

external ext2fs_read_bitmaps : t -> unit = "supermin_ext2fs_read_bitmaps"
external ext2fs_copy_file_from_host : t -> string -> string -> unit = "supermin_ext2fs_copy_file_from_host"
external ext2fs_copy_dir_recursively_from_host : t -> string -> string -> unit = "supermin_ext2fs_copy_dir_recursively_from_host"
