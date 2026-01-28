# Memory Low Code Corrections – `ZAPO_PTC_SUBSTITUTION` (ZSUBST, 28.01.2026)

## 1. Context and Dump Summary

- **Program:** `ZAPO_PTC_SUBSTITUTION`  
- **Include:** `Z_TOP_DATADECLARATIONS`  
- **Method:** `LCL_MASTER_DATA_SUBSTITUTION=>USER_ACTIVITY_BAPI`  
- **Transaction:** `ZSUBST`  
- **Error:** `TSV_TNEW_PAGE_ALLOC_FAILED` (memory low)  
- **Dump artifacts:**  
  - Internal table `LT_GROUP_SUBSET_ITEM_DATA` ~1,878,885 rows × 314 fields  
  - Internal tables `LT_GROUP_SUBSET_ITEM_DATA_T`, `_X`, `_T_X` similarly large  
  - Log table `GT_EXCEL_LOG` ~3.6k rows × 312 fields  

The short dump shows that these very large internal tables are kept in session memory and that the append to one of them (`LT_GROUP_SUBSET_ITEM_DATA_X`) eventually fails due to lack of memory.

---

## 2. Objective

Reduce peak memory usage and avoid `TSV_TNEW_PAGE_ALLOC_FAILED` while preserving the current functional behavior of `ZSUBST`:

- Bound memory usage for BAPI insert buffers.
- Release large subset tables (`LT_GROUP_SUBSET_ITEM_DATA*`) as early as possible.
- Avoid costly `DELETE` inside loops on large tables.
- Limit growth of the log table `GT_EXCEL_LOG`.

---

## 3. Change 1 – Chunked BAPI Inserts (`LT_INSERT_BAPI`)

### 3.1 Problem

Currently all records are accumulated into `LT_INSERT_BAPI` and only then sent to the BAPI. For very large data volumes this leads to a very large internal table in memory and contributes to heap/EM exhaustion.

### 3.2 Proposed Solution

Introduce a package size and call the insert BAPI in **chunks** instead of with the full table.

> **Location:** Method `USER_ACTIVITY_BAPI`, section where `LT_INSERT_BAPI` is filled and the BAPI is called.

#### 3.2.1 Code Change (Template)

```abap
CONSTANTS: gc_pack_size TYPE i VALUE 2000. "tune 1000–5000 as needed

DATA: lt_insert_bapi TYPE STANDARD TABLE OF zty_insert_bapi,
      lt_bapi_chunk  TYPE STANDARD TABLE OF zty_insert_bapi.

CLEAR lt_insert_bapi.

" Loop where items are currently collected for the BAPI
LOOP AT lt_group_subset_item_data_x ASSIGNING FIELD-SYMBOL(<ls_item_x>).

  " Map existing fields as done today
  APPEND VALUE zty_insert_bapi(
    location    = <ls_item_x>-location
    material    = <ls_item_x>-material
    lead_prd    = <ls_item_x>-lead_product
    " ... other fields ...
  ) TO lt_insert_bapi.

  " New: process in chunks to limit memory usage
  IF lines( lt_insert_bapi ) >= gc_pack_size.
    lt_bapi_chunk = lt_insert_bapi.
    PERFORM call_insert_bapi USING lt_bapi_chunk.  " existing FORM / method
    CLEAR lt_insert_bapi.
    FREE  lt_bapi_chunk.
  ENDIF.

ENDLOOP.

" Flush remaining entries
IF lt_insert_bapi IS NOT INITIAL.
  PERFORM call_insert_bapi USING lt_insert_bapi.
ENDIF.

FREE lt_insert_bapi.
```

### 3.3 Expected Effect

- Caps peak memory consumption for the BAPI buffer.
- Frees memory after each chunk is processed.
- No functional change (same data sent, in smaller packages).

---

## 4. Change 2 – Free Large Subset Tables (`LT_GROUP_SUBSET_ITEM_DATA*`)

### 4.1 Problem

The following internal tables are very wide and contain hundreds of thousands to millions of rows:

- `LT_GROUP_SUBSET_ITEM_DATA`
- `LT_GROUP_SUBSET_ITEM_DATA_T`
- `LT_GROUP_SUBSET_ITEM_DATA_X`
- `LT_GROUP_SUBSET_ITEM_DATA_T_X`

They are kept in memory across the full run of `USER_ACTIVITY_BAPI`, so memory usage grows with every processed group/location.

### 4.2 Proposed Solution

1. **Use “slim” structures where possible.**  
   Instead of carrying all 300+ fields, keep only fields required for later steps (BAPI, logging, validation).
2. **Clear and free subset tables as soon as a grouping (e.g. one location/lead product or group number) is finished.**

> **Location:** Method `USER_ACTIVITY_BAPI`, at the end of the outer loop which processes one group/location at a time.

#### 4.2.1 Example: Slim Structure (Optional, If Feasible)

```abap
TYPES: BEGIN OF ty_group_subset_item_slim,
         location     TYPE /your/type,   " adjust to actual types
         material     TYPE /your/type,
         lead_product TYPE /your/type,
         " ... only required fields ...
       END OF ty_group_subset_item_slim.

DATA: lt_group_subset_item_slim TYPE STANDARD TABLE OF ty_group_subset_item_slim.
```

Populate and use `lt_group_subset_item_slim` wherever the full structure is not strictly required.

#### 4.2.2 Clear/Free at End of Group

```abap
" At the end of processing one group/location in USER_ACTIVITY_BAPI:

CLEAR: lt_group_subset_item_data,
       lt_group_subset_item_data_t,
       lt_group_subset_item_data_x,
       lt_group_subset_item_data_t_x.

FREE:  lt_group_subset_item_data,
       lt_group_subset_item_data_t,
       lt_group_subset_item_data_x,
       lt_group_subset_item_data_t_x.
```

Place the above right after all operations for that group are done and before the next group is started.

### 4.3 Expected Effect

- Prevents accumulation of all groups in memory at once.
- Reduces the lifetime of the largest tables, lowering risk of memory exhaustion.

---

## 5. Change 3 – Replace In-Loop `DELETE` with Filtered Rebuild

### 5.1 Problem

Existing pattern (from earlier performance analysis):

```abap
SORT lt_group_item_data BY preceding_product.
SORT lt_group_item_data_x BY item_number.
DELETE ADJACENT DUPLICATES FROM lt_group_item_data COMPARING preceding_product.
DELETE ADJACENT DUPLICATES FROM lt_group_item_data_x COMPARING item_number.

LOOP AT lt_group_item_data_x INTO lw_group_item_data_x.
  lw_flg = sy-tabix.
  READ TABLE lt_group_item_data ASSIGNING <lfs_group_item_data>
           WITH KEY item_number = lw_group_item_data_x-item_number.
  IF sy-subrc <> 0.
    DELETE lt_group_item_data_x INDEX lw_flg.
  ENDIF.
ENDLOOP.
```

- `DELETE` inside the loop causes index shifts and repeated data moves.
- For large tables this is a performance and memory hotspot.

### 5.2 Proposed Solution (Already Consistent With Earlier Fix)

> **Location:** `USER_ACTIVITY_BAPI`, same area as earlier “parallel cursor” optimization (around former lines 7603–7610).

```abap
" Sort tables once for efficient processing
SORT lt_group_item_data   BY item_number.
SORT lt_group_item_data_x BY item_number.
DELETE ADJACENT DUPLICATES FROM lt_group_item_data   COMPARING preceding_product.
DELETE ADJACENT DUPLICATES FROM lt_group_item_data_x COMPARING item_number.

" Optimized loop – build filtered table instead of DELETE in loop
DATA: lt_group_item_data_x_filtered LIKE lt_group_item_data_x.

LOOP AT lt_group_item_data_x INTO lw_group_item_data_x.
  " Efficient lookup via BINARY SEARCH (O(log n))
  READ TABLE lt_group_item_data TRANSPORTING NO FIELDS
       WITH KEY item_number = lw_group_item_data_x-item_number
       BINARY SEARCH.
  IF sy-subrc = 0.
    " Entry exists, keep it
    APPEND lw_group_item_data_x TO lt_group_item_data_x_filtered.
  ENDIF.
ENDLOOP.

" Replace original table with filtered table
lt_group_item_data_x = lt_group_item_data_x_filtered.

" Free temporary table
FREE lt_group_item_data_x_filtered.
```

### 5.3 Expected Effect

- No `DELETE` inside the loop (no repeated array compaction).
- Reduced CPU and fewer memory moves for large tables.
- Better scalability for big data sets.

---

## 6. Change 4 – Control Growth of `GT_EXCEL_LOG`

### 6.1 Problem

`GT_EXCEL_LOG` is a wide table (~312 columns) and reaches several thousand rows. Keeping all success and error logs in memory for the entire run increases heap usage and contributes to memory low situations.

### 6.2 Proposed Solution

1. **Cap success log entries**; keep all errors, but only a limited number of successes.  
2. **Free the log table after download / display.**

> **Location:** `USER_ACTIVITY_BAPI` (and any other place where `GT_EXCEL_LOG` is filled and later output).

#### 6.2.1 Code Change – Limit Success Logs

```abap
CONSTANTS: gc_log_success_max TYPE i VALUE 500.  " adjust as per business need

DATA: gv_log_success_cnt TYPE i.

" When appending to GT_EXCEL_LOG:
IF <ls_log>-status = icon_green_light.
  gv_log_success_cnt = gv_log_success_cnt + 1.
  IF gv_log_success_cnt > gc_log_success_max.
    " Skip further success logs to save memory
    CONTINUE.
  ENDIF.
ENDIF.

APPEND <ls_log> TO gt_excel_log.
```

#### 6.2.2 Code Change – Free Log After Use

```abap
" After ALV display / file download of the log:
PERFORM display_or_download_log USING gt_excel_log.  " existing logic

CLEAR gt_excel_log.
FREE  gt_excel_log.
gv_log_success_cnt = 0.
```

### 6.3 Expected Effect

- Prevents unbounded growth of the log table.
- Releases log memory as soon as the user-facing step is completed.

---

## 7. Supporting / Related Fixes (Already Implemented)

From previous correction documents (`Code_Corrections_ABAP_Performance_Fix.md`, `TS_ABAP_Performance_Fix.md`):

1. **Conversion error fix for `lw_sno` (CONVT_NO_NUMBER).**
2. **Loop optimization using BINARY SEARCH and avoiding `DELETE` inside loops.**

These should remain in place together with the new memory-related corrections in this document.

---

## 8. Testing Checklist

1. **Functional Tests**
   - Re-run the failing UAT / AT1 scenario in transaction `ZSUBST`.
   - Verify all required CVCs/records are still created correctly.
2. **Memory & Performance**
   - Monitor in ST22 / ST02 / SM04 during bulk runs; confirm there is **no new `TSV_TNEW_PAGE_ALLOC_FAILED`**.
   - Check that heap/EM usage plateaus with the chosen `gc_pack_size` (e.g. 2000).
3. **Logging**
   - Confirm that error logs are fully available.
   - Confirm that success logs are present up to the configured cap and that the log is cleared after output.
4. **Regression**
   - Full end-to-end run of `ZSUBST` with typical and high volumes.
   - Compare a small test run before/after to ensure there is no functional deviation.

---

## 9. Notes

- `gc_pack_size` and `gc_log_success_max` can be adjusted per environment depending on volume and available memory.  
- If business requires complete logging for audit, consider persisting logs to a database table in chunks (with commits) instead of keeping all entries in one internal table in memory.  
- The dump `SAPMS380` (`EXTRACT_STRINGS_FROM_SNAP`) is a secondary symptom while displaying large dumps and does **not** require any code change in `ZAPO_PTC_SUBSTITUTION`.


