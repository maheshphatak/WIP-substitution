# Memory Low Dump Analysis – ZAPO_PTC_SUBSTITUTION (ZSUBST, 21.01.2026)

## What failed
- ST22 dump: **GETWA_NOT_ASSIGNED** in `CREATE_CVC_DATA_WITH_LOC` (line ~7351, include `Z_TOP_DATADECLARATIONS`) when dereferencing `<lfs_excel_log_read>` without a successful `READ TABLE`.
- Runtime profile (screenshot 21.01.2026): `Loop at LT_INSERT_BAPI` dominates time/memory; heavy `Delete LT_EXCEL` and repeated `Select ZAPO_PTC_SUBST`; large log table `GT_EXCEL_LOG` (~6.8k rows × 312 fields) retained in memory.

## Root causes
1) **Unassigned field symbol dereference**  
   `READ TABLE gt_excel_log ASSIGNING <lfs_excel_log_read> ...` followed by `<lfs_excel_log>-grpnum = <lfs_excel_log_read>-grpnum` even when `sy-subrc <> 0`.

2) **Unbounded buffering for BAPI inserts**  
   `LT_INSERT_BAPI` accumulates all rows before calling the insert BAPI; no chunking or early FREE → high heap/EM.

3) **Costly deletes on large internal tables**  
   Repeated `DELETE lt_excel`/`DELETE lt_group_item_data_x INDEX ...` inside loops cause copying and reallocation.

4) **Excessive logging**  
   Success rows are appended to `GT_EXCEL_LOG` and kept; table grows but is not trimmed or freed mid-run.

## Corrections to apply

### A. Guard dereference in log handling (dump stopper)
```abap
UNASSIGN <lfs_excel_log_read>.
READ TABLE gt_excel_log ASSIGNING <lfs_excel_log_read>
         WITH KEY location = <lfs_subst_data>-location
                  lead_prd = <lfs_subst_data>-lead_product
                  material = <lfs_subst_data>-material.
lv_flag = abap_false.
IF sy-subrc = 0 AND <lfs_excel_log_read> IS ASSIGNED.
  lv_flag = abap_true.
ENDIF.

IF lt_temp_succ IS NOT INITIAL.
  UNASSIGN <lfs_excel_log>.
  APPEND INITIAL LINE TO gt_excel_log ASSIGNING <lfs_excel_log>.
  IF <lfs_excel_log> IS ASSIGNED.
    IF lv_flag = abap_true AND <lfs_excel_log_read> IS ASSIGNED.
      <lfs_excel_log>-row    = <lfs_excel_log_read>-row.
      <lfs_excel_log>-div    = <lfs_excel_log_read>-div.
      <lfs_excel_log>-grpnum = <lfs_excel_log_read>-grpnum.
    ELSE.
      CLEAR: <lfs_excel_log>-row, <lfs_excel_log>-div, <lfs_excel_log>-grpnum.
    ENDIF.
    <lfs_excel_log>-location = <lfs_subst_data>-location.
    <lfs_excel_log>-lead_prd = <lfs_subst_data>-lead_product.
    <lfs_excel_log>-material = <lfs_subst_data>-material.
    <lfs_excel_log>-message  = 'CVC is Created'.
    <lfs_excel_log>-status   = icon_green_light.
  ENDIF.
ENDIF.
```
Apply the same guard in the error branch (`lt_temp_error`) wherever `<lfs_excel_log_read>` is used.

### B. Chunked BAPI inserts to cap memory
```abap
CONSTANTS: gc_pack_size TYPE i VALUE 2000. "tune: 1000–5000
DATA: lt_insert_bapi TYPE STANDARD TABLE OF zty_insert_bapi,
      lt_bapi_chunk TYPE STANDARD TABLE OF zty_insert_bapi.

CLEAR lt_insert_bapi.
LOOP AT lt_temp_succ ASSIGNING <ls_temp>.
  APPEND VALUE #( " map fields from <ls_temp>
    location = <ls_temp>-location
    material = <ls_temp>-material
    lead_prd = <ls_temp>-lead_product
    "...
  ) TO lt_insert_bapi.

  IF lines( lt_insert_bapi ) >= gc_pack_size.
    lt_bapi_chunk = lt_insert_bapi.
    PERFORM call_insert_bapi USING lt_bapi_chunk. "existing form/method
    CLEAR lt_insert_bapi.
    FREE  lt_bapi_chunk.
  ENDIF.
ENDLOOP.

IF lt_insert_bapi IS NOT INITIAL.
  PERFORM call_insert_bapi USING lt_insert_bapi.
ENDIF.
FREE lt_insert_bapi.
```
- Keeps working set bounded; frees memory after each call.  
- If parallelization is allowed, consider `CALL FUNCTION ... STARTING NEW TASK` per chunk; otherwise keep synchronous.

### C. Replace in-loop deletes with filtered rebuild
```abap
DATA lt_excel_kept LIKE lt_excel.
LOOP AT lt_excel INTO DATA(ls_excel).
  IF ls_excel-skip = abap_true.
    CONTINUE.
  ENDIF.
  APPEND ls_excel TO lt_excel_kept.
ENDLOOP.
lt_excel = lt_excel_kept.
FREE lt_excel_kept.
```
- Avoids index shifting and repeated memory moves shown as “Delete LT_EXCEL” hotspot.

### D. Use hashed/sorted tables for lookups
- Declare `lt_group_item_data_sorted TYPE SORTED TABLE OF ... WITH UNIQUE KEY item_number` (or HASHED) for `READ ... BINARY SEARCH / O(1)`.
- Prevents full scans inside high-volume loops (`Loop at LT_GROUP_SUBSET_ITEM_DATA_T` in trace).

### E. Trim and scope logging
- Keep only failures in `gt_excel_log` or cap successes:  
  `IF <ls_log>-status = icon_green_light. CONTINUE. ENDIF.` when log table exceeds a threshold (e.g., 500).  
- `CLEAR gt_excel_log.` / `FREE gt_excel_log.` after download/export.

### F. Database access
- Cache `ZAPO_PTC_SUBST` once per run into an internal table; avoid per-iteration `SELECT`.
- Ensure SELECT uses needed fields only; add proper WHERE filters to reduce result size.

## Test checklist
- Re-run failing UAT scenario; confirm no `GETWA_NOT_ASSIGNED` and no MEMORY_LOW.
- Monitor memory (ST02/SM04) during bulk run; verify heap/EM plateau with chunk size.
- Compare runtime profile: `Loop at LT_INSERT_BAPI` and `Delete LT_EXCEL` should drop significantly.
- Validate functional parity: created CVCs/log rows match previous logic.

## Notes
- Tune `gc_pack_size` based on typical dataset and RFC/BAPI limits.  
- Ensure form/method `call_insert_bapi` handles partial commits and returns/merges messages.  
- If business requires keeping all success logs, persist to DB table with commit after chunk instead of keeping full internal table.

