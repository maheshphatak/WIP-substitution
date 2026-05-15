# ZAPO_MATERIAL_BALANCE — Implementation & Code Change Document

**Include:** `ZAPO_MATERIAL_BALANCE_CLS`  
**Reference source (updated in workspace):** `WIP2 Substitution/Matbal/ZAPO_MATERIAL_BALANCE_CLS.txt`  
**Change IDs:** AD1K917524 (PROD_QTY totals / performance), TEST variant / display fixes  
**Date:** May 2026  

---

## 1. Purpose

This document describes the consolidated ABAP implementation applied for:

| # | Topic | Outcome |
|---|--------|---------|
| 1 | Variant `TEST-MATBAL` → **No Data Found** on Display | Mock path only in true dev; production/UAT uses real SNP log |
| 2 | Blank **Total Demand / Total Supply** on `PROD_QTY` rows | Totals derived from supply/demand aggregates |
| 3 | **Region-wise** columns missing (only totals visible) | `D_OTHR` / `S_OTHR` + `ZAPO_MATBAL_ITEM` fallback for `PROD_QTY` |
| 4 | Performance | Pre-aggregation tables in `populate_demand_qty` (no extra loops per row) |

**Out of scope (per functional sign-off):** Changes to **Opening Stock** / **Closing Stock** scaling logic in `populate_other_qty`.

---

## 2. Root causes (summary)

### 2.1 Display — No Data Found (`TEST-MATBAL`)

- Any `p_orun` containing `TEST` triggered **mock mode** (`upd_mock_data_gen_matbal`).
- CSV upload inside mock method was **commented out** → empty internal tables → nothing saved to `ZAPO_MATBAL_HRD` / `ZAPO_MATBAL_ITEM`.
- Display reads only persisted Z-tables; empty tables → message **No Data Found (037)**.

### 2.2 `PROD_QTY` blank totals

- Rows created via `populate_no_dmd_prod_qty` have **no regional** `D_*` / `S_*` buckets.
- `populate_demand_qty` summed only regional fields → `tot_dmd` / `tot_supply` stayed initial.

### 2.3 Region columns not shown

- Dynamic columns built from `lt_reg_off` (planning book / saved items).
- `ZAPO_MATBAL_ITEM` rows skipped when both regional demand and supply are initial (`CONTINUE` in `append_for_db_upd`).
- `PROD_QTY` rows often had header totals only → no item lines → display built no `D_*` / `S_*` columns.

---

## 3. Design principle — mock mode guard

Mock behaviour is enabled **only** when **both** are true:

```abap
lv_is_mock_mode = xsdbool( c_dev = abap_true AND p_orun CP 'TEST*' ).
```

| Environment | `c_dev` | `p_orun` | Behaviour |
|-------------|---------|----------|-----------|
| Production/UAT | space | `TEST-MATBAL` | **Real log fetch** (same as `P1005781:...`) |
| Dev + CSV folder | X | `TEST*` | Mock CSV load (if `p_file` filled) |
| Any | any | Real session name | Real log fetch |

---

## 4. Code changes by method

### 4.1 `upd_mock_data_gen_matbal`

**Change:** Re-enable CSV upload when `c_dev = abap_true` **and** `p_file` is not initial.

```abap
IF c_dev = abap_true AND p_file IS NOT INITIAL.
  lv_file_path = p_file && '\csv'.
  ycl_helper_csv_upd_dwn=>upload_csv_to_internal_table( ... ).
ENDIF.
```

### 4.2 `generate_material_balance`

**Before:** `IF p_orun CS 'TEST'.`  
**After:** `IF lv_is_mock_mode = abap_true.`

### 4.3 `calulate_mat_bal_demand`

**Before:** `IF NOT p_orun CS 'TEST'.` → `fetch_pb_data`.  
**After:** `IF lv_is_mock_mode = abap_false.` → `fetch_pb_data`.

### 4.4 `create_dyn_tab`

- Local flag `lv_is_mock_mode` at method start.
- BW region text select: `NOT p_orun CS 'TEST'` → `lv_is_mock_mode = abap_false`.
- Region filter on screen: `p_orun CS 'TEST'` → `lv_is_mock_mode = abap_true`.
- **Display:** If `lt_reg_off` empty but `gt_matbal_hrd` has data, append `'OTHR'` so regional columns still appear.

### 4.5 `validate_screen`

**Before:** `IF p_orun CS 'TEST'.` → skip SNP session validation.  
**After:** `IF lv_is_mock_mode = abap_true.` only in dev.

### 4.6 `populate_demand_qty` (AD1K917524)

**A. Pre-aggregation (once per run)**

| Table | Key | Source |
|-------|-----|--------|
| `lt_supply_src_sum` | locno_fr, matnr, month | `gt_supply_dmn_cust_loc-trans` |
| `lt_supply_out_sum` | matnr, month | `gt_output_dmd-deliv` |
| `lt_demand_in_sum` | matnr, month | `gt_input_dmd-deman` |

**B. SNZ ratio fallback**

- Flag `lv_dmd_ratio_used`: if SNZ/S ratio not applied, copy raw `D_<reg>` to output (`<lfs_comp2> = <lfs_comp>`).

**C. `PROD_QTY` totals**

When `added_by_method = 'PROD_QTY'` and totals initial:

1. Supply from `lt_supply_src_sum` (source plant).
2. Else from `lt_supply_out_sum`.
3. Demand from `lt_demand_in_sum`.
4. If demand initial and supply not → demand = supply.
5. Set `D_OTHR` / `S_OTHR` on output structure for ALV.

### 4.7 `append_for_db_upd`

- Track `lv_item_written` in region loop.
- After loop: for `PROD_QTY` with totals but no regional item lines → insert **`ZAPO_MATBAL_ITEM`** with `reg_off = 'OTHR'`, `demand_qty` / `supply_qty` from totals (KG ÷ 1000 when applicable).

### 4.8 Not changed

- `populate_other_qty` — opening/closing stock scaling (unchanged).
- `get_opening_stock` / `get_closing_stock`.

---

## 5. Behaviour notes (FAQ from analysis)

### Supply Location vs Ship-to Party

`SUPPLY_PLANT` is always an **APO location number** (`/sapapo/locno`). It may **look** like ship-to when customer locations use the same numbering as ECC ship-to; there is no separate SHP column in the report key.

### Demand ≠ Supply

Expected when ET vs IT paths differ, lanes are split, captive/vendor flows apply, or `PROD_QTY` totals use aggregated fallbacks.

### Opening stock vs Product + SHP

Stock is stored at **supply plant / location** level (`matnr + scr_plant + supply_plant + cal_month`), not per ship-to. Multiple customers sharing a plant share one stock line (with ratio scaling in `populate_other_qty`).

---

## 6. Transport & test plan

### 6.1 Prerequisites

1. Transport include `ZAPO_MATERIAL_BALANCE_CLS` to AD1.
2. For **dev mock** runs: set `c_dev`, `p_file` pointing to `\csv` folder with mock extracts.

### 6.2 Test cases

| # | Action | Selection | Expected |
|---|--------|-----------|----------|
| T1 | Generate | `p_orun = P1005781:001:2026.04.29-20:42:09`, real log | Data in ALV; Z-tables populated |
| T2 | Display | Same session after T1 | Same data; regional columns from `ZAPO_MATBAL_ITEM` |
| T3 | Generate | `TEST-MATBAL`, `c_dev` = space (prod) | Real log path **or** valid SNP name; **not** empty mock |
| T4 | Generate | `TEST-MATBAL`, `c_dev` = X, `p_file` set | CSV loaded; generate + save |
| T5 | Display | `TEST-MATBAL` after T4 save | No **No Data Found**; `D_OTHR`/`S_OTHR` if only PROD_QTY totals |
| T6 | PROD_QTY row | Log with production-only materials | **Total Demand/Supply** filled; not blank |

### 6.3 SQL checks (AD1)

```sql
SELECT sessionname, matnr, scr_plant, supply_plant, cal_month,
       tota_demand, total_supply, prod_qty
  FROM zapo_matbal_hrd
 WHERE sessionname = '<your_session>'
```

```sql
SELECT sessionname, matnr, reg_off, demand_qty, supply_qty
  FROM zapo_matbal_item
 WHERE sessionname = '<your_session>'
```

---

## 7. File list

| File | Description |
|------|-------------|
| `ZAPO_MATERIAL_BALANCE_CLS.txt` | Full include — **apply this in SE38/SE80** |
| `ZAPO_MATERIAL_BALANCE_Implementation_CodeChange.md` | This document |
| `Matbal_PRODQTY_Totals_Performance_CodeChange.md` | Detail on AD1K917524 only |
| `ZAPO_MATERIAL_BALANCE_TEST_VARIANT_Fix_Full_Code.md` | Detail on TEST variant guard |

---

## 8. Rollback

Revert `lv_is_mock_mode` conditions back to `p_orun CS 'TEST'` / `NOT p_orun CS 'TEST'` and comment CSV block in `upd_mock_data_gen_matbal` if mock must run in non-dev again (not recommended for production).

---

*End of document.*
