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

(** Implements [--build -f ext2] minimal initrd which is required
    to mount the ext2 filesystem at runtime.

    See also the {!Format_ext2} module. *)

val build_initrd : int -> string -> string -> string -> unit
(** [build_initrd debug tmpdir modpath initrd] creates the minimal
    initrd required to mount the ext2 filesystem at runtime.

    A small, whitelisted selection of kernel modules is taken
    from [modpath], just enough to mount the appliance.

    The output is the file [initrd]. *)
