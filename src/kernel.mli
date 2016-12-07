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

(** For [--build -f ext2] this module chooses a kernel to use
    and either links to it or copies it.

    See also the {!Ext2} module. *)

val build_kernel : int -> string -> string option -> bool -> string -> string -> string * string
(** [build_kernel debug host_cpu dtb_wildcard copy_kernel kernel dtb]
    chooses the kernel to use and links to it or copies it into the
    appliance directory.

    The output is written to the file [kernel].

    The function returns the [kernel_version, modpath] tuple as a
    side-effect of locating the kernel.

    The [--dtb] option is also handled here, but that support is
    now effectively obsolete and will be removed in future. *)
