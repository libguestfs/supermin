(* supermin 5
 * Copyright (C) 2009-2016 Red Hat Inc.
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

(** Implements [--build -f chroot]. *)

val build_ext2 : int -> string -> Package_handler.file list -> string -> string -> string -> int64 option -> string option -> unit
(** [build_ext2 debug basedir files modpath kernel_version appliance size
    packagelist_file] copies all the files from [basedir] plus the
    list of [files] into a newly created ext2 filesystem called [appliance].

    Kernel modules are also copied in from the local [modpath]
    to the fixed path in the appliance [/lib/modules/<kernel_version>].

    libext2fs is used to populate the ext2 filesystem. *)
