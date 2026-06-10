# Material Balance — WIP Optimisation Code Change

**Program:** `ZAPO_MATERIAL_BALANCE`  
**Include:** `ZAPO_MATERIAL_BALANCE_CLS`  
**Test log:** `P1005781:001:2026.04.29-20:42:09` (Division 14)  
**Selection:** Generate Material Balance + **WIP Optimisation** checked  

**SAP AD1 note:** Live SQL validation was not possible from this workspace (MCP RFC unavailable). Corrections are based on static code analysis and SNP log table mapping.

---

## 1. Functional requirement (WIP Optimisation ON)

When **WIP Optimisation** is selected, report quantities must match the SNP Optimiser log **without** regional proration, depot lane splits, or ratio scaling.

| Report field | SNP source | Table | Log field | Aggregation |
|--------------|------------|-------|-----------|-------------|
| **Total Demand** | ET_DEMAND | `/SAPAPO/SNPOPDMD` | `DEMAN` | SUM by Product + Location + Calendar month (all buckets) |
| **Opening Stock** | ET_LOCMAT | `/SAPAPO/SNPOPLMA` | `STOCK` | Value for Product + Location (initial warehouse stock) |
| **Total Supply** | IT_DEMAND | `/SAPAPO/SNPOPDMN` | `DELIV` | SUM by Product + Location + Calendar month (all buckets) |

**Table name clarification**

- Requirement text mentions `/SAPAPO/SNPOPDEM` / `PRODU` — that is **production output** (`/SAPAPO/SNPOPPRO`), not IT demand delivery.
- For **Total Supply = IT Demand delivery quantity**, the correct source is **`/SAPAPO/SNPOPDMN-DELIV`** (already read into `gt_snpopdmn` in `fetch_demand_details`).

---

## 2. Root cause analysis

### 2.1 Total Demand wrong

**Standard path (WIP Optimisation OFF):**

1. `calculate_inp_dmd` aggregates `DEMAN` into `gt_input_dmd`.
2. `populate_supply` creates rows per customer / transport lane / region.
3. `populate_demand_qty` applies:
   - Regional `D_<REG>` / `S_<REG>` buckets
   - SNZ supply-ratio proration
   - Unfulfilled demand at depot level
   - Zero-demand month padding in `calculate_inp_dmd`

**Result:** `TOT_DMD` is a **derived allocation**, not a direct SUM of `SNPOPDMD-DEMAN`.

### 2.2 Opening Stock wrong

**Standard path:**

1. Opening stock is read from `SNPOPLMA`, `SNPOPLPR`, `SNPOPMLO` in `append_to_outtab_dyn` / `populate_no_dmd_opng_stk`.
2. `populate_other_qty` **scales** opening stock:

```abap
ls_fin_qty-opng_stk = ls_fin_qty-opng_stk *
  ( ls_fin_qty-tot_supply + ls_fin_qty-captive_supply ) / <lfs_subtotal>-supply_sum.
```

**Result:** Report opening stock ≠ `SNPOPLMA-STOCK` from the log.

### 2.3 Total Supply wrong

**Standard path:**

1. `calc_spld_dmn_cust_wise` correctly sums `DELIV` into `gt_output_dmd`.
2. `populate_supply` redistributes supply across lanes, depots, captive paths, and regions.

**Result:** `TOT_SUPPLY` ≠ SUM of `SNPOPDMN-DELIV`.

### 2.4 Additional WIP material gap

ECC fetch in `fill_selection_matnr` allows only **`MTART = ZFRT`**. WIP optimizer products are often **`ZWIP`**, so materials can be dropped from `gt_ecc_mat_master` and excluded from output.

---

## 3. Design — dedicated WIP Optimisation path

When `p_wip_opt = abap_true`:

| Step | Standard | WIP Optimisation |
|------|----------|------------------|
| Intermediate demand/supply calc | `calulate_mat_bal_demand` | Skipped (only `find_mat_prod_plant`) |
| Dynamic regions | Planning book / BW regions | **`OTHR` only** |
| Row build | `populate_supply` → `populate_demand_qty` | **`build_wip_opt_matbal`** |
| Ratio scaling | `populate_other_qty` | **Skipped** |
| ECC material types | ZFRT | **ZFRT + ZWIP** |

New method **`build_wip_opt_matbal`**:

1. Pre-aggregate `gt_snpopdmd-DEMAN` → `lt_dmd_sum` (matnr, locno, month).
2. Pre-aggregate `gt_snpopdmn-DELIV` → `lt_supply_sum`.
3. Read `gt_snpoplma-STOCK` → `lt_opng_stk` (matnr, locno).
4. Build one row per key: `src_plant = supply_plant = locno`, set:
   - `tot_dmd` = aggregated DEMAN
   - `tot_supply` = aggregated DELIV
   - `opng_stk` = LOCMAT STOCK (unscaled)
   - `D_OTHR` / `S_OTHR` = same totals
5. Persist via `append_for_db_upd` → `ZAPO_MATBAL_HRD` / `ZAPO_MATBAL_ITEM`.

---

## 4. Code changes applied

### 4.1 Selection screen / TOP include (manual in SAP if not present)

Add checkbox parameter (align name with your screen):

```abap
PARAMETERS p_wip_opt AS CHECKBOX.
```

Add to class definition (`ZAPO_MATERIAL_BALANCE_CLS` def or TOP):

```abap
DATA p_wip_opt TYPE abap_bool.
```

Add method declaration:

```abap
METHODS build_wip_opt_matbal.
```

### 4.2 `generate_material_balance`

```abap
IF p_wip_opt = abap_true.
  me->find_mat_prod_plant( ).
ELSE.
  me->calulate_mat_bal_demand( ).
ENDIF.

me->create_dyn_tab( ).

IF p_wip_opt = abap_true.
  me->build_wip_opt_matbal( ).
ELSE.
  me->populate_supply( ).
  me->get_subtol_for_dmd( ).
  me->populate_demand_qty( ).
  me->populate_other_qty( ).
ENDIF.
```

### 4.3 `create_dyn_tab`

After `CASE r_gen` / `ENDCASE`:

```abap
IF p_wip_opt = abap_true AND r_gen = abap_true.
  CLEAR lt_reg_off.
  APPEND 'OTHR' TO lt_reg_off.
ENDIF.
```

### 4.4 `fill_selection_matnr`

When `p_wip_opt = abap_true`, add **`ZWIP`** to MTART selection (in addition to `ZFRT`).

### 4.5 New method `build_wip_opt_matbal`

Full implementation is in:

`WIP2 Substitution/Matbal/ZAPO_MATERIAL_BALANCE_CLS.txt`

(Search for `METHOD build_wip_opt_matbal`.)

---

## 5. Validation steps (SAP AD1)

### 5.1 Reference totals from log (SE16 / SQVI)

Replace `<session_id>` with SNP session GUID from `/SAPAPO/SNPOPKEY`.

**Total Demand (ET_DEMAND)**

```sql
SELECT m.MATNR, l.LOCNO, b.CAL_MONTH, SUM(d.DEMAN) AS TOT_DMD
  FROM /SAPAPO/SNPOPDMD d
  JOIN /SAPAPO/MATKEY m ON d.MATID = m.MATID
  JOIN /SAPAPO/LOC   l ON d.LOCID = l.LOCID
  -- map bucket d.BUCKE to calendar month via your bucket table
 WHERE d.SESSIONID = '<session_id>'
 GROUP BY m.MATNR, l.LOCNO, b.CAL_MONTH
```

**Total Supply (IT_DEMAND)**

```sql
SELECT m.MATNR, l.LOCNO, SUM(n.DELIV) AS TOT_SUPPLY
  FROM /SAPAPO/SNPOPDMN n
  JOIN /SAPAPO/MATKEY m ON n.MATID = m.MATID
  JOIN /SAPAPO/LOC   l ON n.LOCID = l.LOCID
 WHERE n.SESSIONID = '<session_id>'
 GROUP BY m.MATNR, l.LOCNO, cal_month
```

**Opening Stock (ET_LOCMAT)**

```sql
SELECT m.MATNR, l.LOCNO, ma.STOCK
  FROM /SAPAPO/SNPOPLMA ma
  JOIN /SAPAPO/MATKEY m ON ma.MATID = m.MATID
  JOIN /SAPAPO/LOC   l ON ma.LOCID = l.LOCID
 WHERE ma.SESSIONID = '<session_id>'
```

### 5.2 Report reconciliation

For log `P1005781:001:2026.04.29-20:42:09`, Division `14`:

| Check | Row key | Expected |
|-------|---------|----------|
| T1 | PY131C1KC95R / 3903 / 05.2026 | `Total Demand` = SUM `DEMAN` from ET_DEMAND |
| T2 | Same row | `Opening Stock` = `STOCK` from ET_LOCMAT for mat+loc |
| T3 | Same row | `Total Supply` = SUM `DELIV` from IT_DEMAND |
| T4 | WIP Optimisation OFF | Totals **may differ** (by design — allocation path) |
| T5 | WIP Optimisation ON | Totals **must match** log sums exactly |

### 5.3 Persisted data

```sql
SELECT matnr, scr_plant, supply_plant, cal_month,
       tota_demand, total_supply, opng_stk
  FROM zapo_matbal_hrd
 WHERE sessionname = 'P1005781:001:2026.04.29-20:42:09'
   AND div = '14'
```

---

## 6. Transport checklist

- [ ] TOP/SCR: `p_wip_opt` checkbox on selection screen
- [ ] Class definition: declare `build_wip_opt_matbal`
- [ ] Include `ZAPO_MATERIAL_BALANCE_CLS`: apply changes from `ZAPO_MATERIAL_BALANCE_CLS.txt`
- [ ] Text symbol `091` (optional): "Building WIP Optimisation Material Balance..."
- [ ] Activate program + includes
- [ ] Generate with WIP Optimisation ON for `P1005781:001:...`
- [ ] Compare ALV vs SE16 reference queries above

---

## 7. Out of scope (unchanged)

- Closing stock, production qty, captive qty in WIP path (still from log tables if extended later; not ratio-scaled in WIP path because `populate_other_qty` is skipped).
- Opening/closing stock ratio logic in **non-WIP** mode (unchanged per prior sign-off).

---

*End of document.*
