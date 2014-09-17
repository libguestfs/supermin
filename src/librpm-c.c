/* supermin 5
 * Copyright (C) 2014 Red Hat Inc.
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
 */

#include <config.h>

#include <stdlib.h>
#include <string.h>
#include <glob.h>
#include <assert.h>
#include <stdbool.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

#ifdef HAVE_LIBRPM

#include <rpm/header.h>
#include <rpm/rpmdb.h>
#include <rpm/rpmlib.h>
#include <rpm/rpmlog.h>
#include <rpm/rpmts.h>

static rpmlogCallback old_log_callback;

static int
supermin_rpm_log_callback (rpmlogRec rec, rpmlogCallbackData data)
{
  fprintf (stderr, "supermin: rpm: lib: %s%s",
           rpmlogLevelPrefix (rpmlogRecPriority (rec)),
           rpmlogRecMessage (rec));
  return 0;
}

struct librpm_data
{
  rpmts ts;
  int debug;
};

static void librpm_handle_closed (void) __attribute__((noreturn));

static void
librpm_handle_closed (void)
{
  caml_failwith ("librpm: function called on a closed handle");
}

static void
librpm_raise_multiple_matches (int occurrences)
{
  caml_raise_with_arg (*caml_named_value ("librpm_multiple_matches"),
                       Val_int (occurrences));
}

#define Librpm_val(v) (*((struct librpm_data *)Data_custom_val(v)))
#define Val_none Val_int(0)
#define Some_val(v) Field(v,0)

static void
librpm_finalize (value rpmv)
{
  struct librpm_data data = Librpm_val (rpmv);

  if (data.ts) {
    rpmtsFree (data.ts);

    rpmlogSetCallback (old_log_callback, NULL);
  }
}

static struct custom_operations librpm_custom_operations = {
  (char *) "librpm_custom_operations",
  librpm_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default
};

static value
Val_librpm (struct librpm_data *data)
{
  CAMLparam0 ();
  CAMLlocal1 (rpmv);

  rpmv = caml_alloc_custom (&librpm_custom_operations,
                            sizeof (struct librpm_data), 0, 1);
  Librpm_val (rpmv) = *data;
  CAMLreturn (rpmv);
}

value
supermin_rpm_is_available (value unit)
{
  return Val_true;
}

value
supermin_rpm_version (value unit)
{
  return caml_copy_string (RPMVERSION);
}

value
supermin_rpm_open (value debugv)
{
  CAMLparam1 (debugv);
  CAMLlocal1 (rpmv);
  struct librpm_data data;
  int res;
  rpmlogLvl lvl;

  data.debug = debugv == Val_none ? 0 : Int_val (Some_val (debugv));

  switch (data.debug) {
  case 3:
    lvl = RPMLOG_INFO;
    break;
  case 2:
    lvl = RPMLOG_NOTICE;
    break;
  case 1:
    lvl = RPMLOG_WARNING;
    break;
  case 0:
  default:
    lvl = RPMLOG_ERR;
    break;
  }

  rpmSetVerbosity (lvl);
  old_log_callback = rpmlogSetCallback (supermin_rpm_log_callback, NULL);

  res = rpmReadConfigFiles (NULL, NULL);
  if (res == -1)
    caml_failwith ("rpm_open: rpmReadConfigFiles failed");

  data.ts = rpmtsCreate ();
  if (data.ts == NULL)
    caml_failwith ("rpm_open: rpmtsCreate failed");

  rpmv = Val_librpm (&data);
  CAMLreturn (rpmv);
}

value
supermin_rpm_close (value rpmv)
{
  CAMLparam1 (rpmv);

  librpm_finalize (rpmv);

  /* So we don't double-free in the finalizer. */
  Librpm_val (rpmv).ts = NULL;

  CAMLreturn (Val_unit);
}

value
supermin_rpm_installed (value rpmv, value pkgv)
{
  CAMLparam2 (rpmv, pkgv);
  CAMLlocal2 (rv, v);
  struct librpm_data data;
  rpmdbMatchIterator iter;
  int count, i;
  Header h;

  data = Librpm_val (rpmv);
  if (data.ts == NULL)
    librpm_handle_closed ();

  iter = rpmtsInitIterator (data.ts, RPMTAG_NAME, String_val (pkgv), 0);
  if (iter == NULL)
    caml_raise_not_found ();

  count = rpmdbGetIteratorCount (iter);
  if (data.debug >= 2)
    printf ("supermin: rpm: installed: %d occurrences for '%s'\n", count, String_val (pkgv));

  rv = caml_alloc (count, 0);
  i = 0;

  while ((h = rpmdbNextIterator (iter)) != NULL) {
    HeaderIterator hi;
    rpmtd td;
    uint32_t *val;
    bool stored_vals[5] = { false };

    v = caml_alloc (5, 0);
    hi = headerInitIterator (h);
    td = rpmtdNew ();
    while (headerNext (hi, td) == 1) {
      switch (rpmtdTag (td)) {
      case RPMTAG_NAME:
        Store_field (v, 0, caml_copy_string (rpmtdGetString (td)));
        stored_vals[0] = true;
        break;
      case RPMTAG_EPOCH:
        val = rpmtdGetUint32 (td);
        Store_field (v, 1, Val_int ((int) *val));
        stored_vals[1] = true;
        break;
      case RPMTAG_VERSION:
        Store_field (v, 2, caml_copy_string (rpmtdGetString (td)));
        stored_vals[2] = true;
        break;
      case RPMTAG_RELEASE:
        Store_field (v, 3, caml_copy_string (rpmtdGetString (td)));
        stored_vals[3] = true;
        break;
      case RPMTAG_ARCH:
        Store_field (v, 4, caml_copy_string (rpmtdGetString (td)));
        stored_vals[4] = true;
        break;
      }
      rpmtdFreeData (td);
    }
    /* Make sure to properly initialize all the fields of the returned
     * rmp_t, even if some tags are missing in the RPM header.
     */
    if (!stored_vals[0])
      Store_field (v, 0, caml_copy_string (String_val (pkgv)));
    if (!stored_vals[1])
      Store_field (v, 1, Val_int (0));
    if (!stored_vals[2])
      Store_field (v, 2, caml_copy_string ("0"));
    if (!stored_vals[3])
      Store_field (v, 3, caml_copy_string ("unknown"));
    if (!stored_vals[4])
      Store_field (v, 4, caml_copy_string ("unknown"));
    Store_field (rv, i, v);

    rpmtdFree (td);
    headerFreeIterator (hi);
    ++i;
  }

  rpmdbFreeIterator (iter);

  CAMLreturn (rv);
}

value
supermin_rpm_pkg_requires (value rpmv, value pkgv)
{
  CAMLparam2 (rpmv, pkgv);
  CAMLlocal1 (rv);
  struct librpm_data data;
  rpmdbMatchIterator iter;
  int count, i;
  Header h;
  rpmtd td;

  data = Librpm_val (rpmv);
  if (data.ts == NULL)
    librpm_handle_closed ();

  iter = rpmtsInitIterator (data.ts, RPMDBI_LABEL, String_val (pkgv), 0);
  if (iter == NULL)
    caml_raise_not_found ();

  count = rpmdbGetIteratorCount (iter);
  if (data.debug >= 2)
    printf ("supermin: rpm: pkg_requires: %d occurrences for '%s'\n", count, String_val (pkgv));
  if (count != 1)
    librpm_raise_multiple_matches (count);

  h = rpmdbNextIterator (iter);
  assert (h != NULL);

  td = rpmtdNew ();
  i = headerGet (h, RPMTAG_REQUIRENAME, td, HEADERGET_MINMEM);
  if (i != 1)
    caml_failwith ("rpm_pkg_requires: headerGet failed");

  rv = caml_alloc (rpmtdCount (td), 0);
  for (i = 0; i < rpmtdCount (td); ++i)
    Store_field (rv, i, caml_copy_string (rpmtdNextString (td)));

  rpmtdFreeData (td);
  rpmtdFree (td);

  rpmdbFreeIterator (iter);

  CAMLreturn (rv);
}

static rpmdbMatchIterator
createProvidesIterator (rpmts ts, const char *what)
{
  rpmdbMatchIterator mi = NULL;

  if (what[0] != '/') {
    mi = rpmtsInitIterator(ts, RPMDBI_PROVIDENAME, what, 0);
    if (mi != NULL)
      return mi;
  }
  mi = rpmtsInitIterator(ts, RPMDBI_INSTFILENAMES, what, 0);
  if (mi != NULL)
    return mi;

  mi = rpmtsInitIterator(ts, RPMDBI_PROVIDENAME, what, 0);

  return mi;
}

value
supermin_rpm_pkg_whatprovides (value rpmv, value pkgv)
{
  CAMLparam2 (rpmv, pkgv);
  CAMLlocal1 (rv);
  struct librpm_data data;
  rpmdbMatchIterator iter;
  int count, i;
  Header h;

  data = Librpm_val (rpmv);
  if (data.ts == NULL)
    librpm_handle_closed ();

  iter = createProvidesIterator (data.ts, String_val (pkgv));
  if (iter == NULL)
    caml_raise_not_found ();

  count = rpmdbGetIteratorCount (iter);
  if (data.debug >= 2)
    printf ("supermin: rpm: pkg_whatprovides: %d occurrences for '%s'\n", count, String_val (pkgv));

  rv = caml_alloc (count, 0);
  i = 0;

  while ((h = rpmdbNextIterator (iter)) != NULL) {
    rpmtd td;
    int ret;

    td = rpmtdNew ();
    ret = headerGet (h, RPMTAG_NAME, td, HEADERGET_MINMEM);
    if (ret != 1)
      caml_failwith ("rpm_pkg_whatprovides: headerGet failed");

    Store_field (rv, i, caml_copy_string (rpmtdGetString (td)));

    rpmtdFreeData (td);
    rpmtdFree (td);
    ++i;
  }

  rpmdbFreeIterator (iter);

  CAMLreturn (rv);
}

value
supermin_rpm_pkg_filelist (value rpmv, value pkgv)
{
  CAMLparam2 (rpmv, pkgv);
  CAMLlocal2 (rv, v);
  struct librpm_data data;
  rpmdbMatchIterator iter;
  int count, i;
  Header h;
  rpmfi fi;
  const rpmfiFlags fiflags = RPMFI_NOHEADER | RPMFI_FLAGS_QUERY | RPMFI_NOFILEDIGESTS;

  data = Librpm_val (rpmv);
  if (data.ts == NULL)
    librpm_handle_closed ();

  iter = rpmtsInitIterator (data.ts, RPMDBI_LABEL, String_val (pkgv), 0);
  if (iter == NULL)
    caml_raise_not_found ();

  count = rpmdbGetIteratorCount (iter);
  if (data.debug >= 2)
    printf ("supermin: rpm: pkg_filelist: %d occurrences for '%s'\n", count, String_val (pkgv));
  if (count != 1)
    librpm_raise_multiple_matches (count);

  h = rpmdbNextIterator (iter);
  assert (h != NULL);

  fi = rpmfiNew (data.ts, h, RPMTAG_BASENAMES, fiflags);

  count = rpmfiFC (fi);
  if (count < 0)
    count = 0;

  rv = caml_alloc (count, 0);
  i = 0;

  fi = rpmfiInit (fi, 0);
  while (rpmfiNext (fi) >= 0) {
    const char *fn;

    v = caml_alloc (2, 0);
    fn = rpmfiFN(fi);
    Store_field (v, 0, caml_copy_string (fn));
    if (rpmfiFFlags (fi) & RPMFILE_CONFIG)
      Store_field (v, 1, Val_long (1)); /* FileConfig */
    else
      Store_field (v, 1, Val_long (0)); /* FileNormal */
    Store_field (rv, i, v);
    ++i;
  }
  rpmfiFree(fi);

  rpmdbFreeIterator (iter);

  CAMLreturn (rv);
}

#else

value
supermin_rpm_is_available (value unit)
{
  return Val_false;
}

value
supermin_rpm_version (value unit)
{
  abort ();
}

value
supermin_rpm_open (value debugv)
{
  abort ();
}

value
supermin_rpm_close (value rpmv)
{
  abort ();
}

value
supermin_rpm_installed (value rpmv, value pkgv)
{
  abort ();
}

value
supermin_rpm_pkg_requires (value rpmv, value pkgv)
{
  abort ();
}

value
supermin_rpm_pkg_whatprovides (value rpmv, value pkgv)
{
  abort ();
}

value
supermin_rpm_pkg_filelist (value rpmv, value pkgv)
{
  abort ();
}

#endif
