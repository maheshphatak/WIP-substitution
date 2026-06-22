# Material Balance — WIP2 Optimisation: Both FG Materials at Production Plant

**Program:** `ZAPO_SNPOP_REPORT` → `ZAPO_MATERIAL_BALANCE`  
**Include:** `ZAPO_MATERIAL_BALANCE_CLS`  
**Variant:** `TEST-MATBAL`  
**Log:** `P1005781:001:2026.04.29-20:42:09` | Division **14** | Month **05.2026**

---

## 1. Screenshot comparison (your test case)

### WIP2 Optimisation **disabled** (Screenshot 1 — expected layout)

| Plant | Sup Loc | Product | Added By Method |
|-------|---------|---------|-----------------|
| **3903** (HMD - POY- CP 10) | **3903** | **PY131C1KC95R** | PROD_QTY |
| **3903** | **3903** | **PY132C6KM95R** | PROD_QTY |

Two FG materials at **production plant 3903**.

### WIP Optimiser **ticked** (Screenshot 2 — before fix)

| Plant | Sup Loc | Product | Added By Method |
|-------|---------|---------|-----------------|
| **3000025464** (Dummy Customer) | **3000025464** | PY131C1KC95R | WIP_OPT |

Only **one** material; location is **ship-to/customer**, not plant **3903**.  
**PY132C6KM95R** is missing.

---

## 2. Root cause

| # | Issue | Cause in code |
|---|--------|----------------|
| 1 | Wrong location (3000025464) | `build_wip_opt_matbal` used **log `locno` from IT_DEMAND/ET_DEMAND** (customer) as `SRC_PLANT` / `SUPPLY_PLANT` |
| 2 | Only one material | Row keys built only from **customer-level** demand/supply aggregates; **PY132C6KM95R** has production at plant **3903** but no customer IT line in the aggregated set |
| 3 | Missing PROD_QTY alignment | WIP path skipped **`calculate_prod_qty`**, so **`gt_prod_qty`** (driver for PROD_QTY rows in standard path) was not populated |

Standard path (WIP off) creates rows via **`populate_no_dmd_prod_qty`** using **`gt_prod_qty`** at **plant** level — that is why both materials appear at **3903**.

---

## 3. Expected output (WIP Optimiser ticked)

Same **row set** as WIP-off for materials and plant:

| Plant | Sup Loc | Product | Method | Quantities |
|-------|---------|---------|--------|------------|
| 3903 | 3903 | PY131C1KC95R | WIP_OPT | Log-exact DEMAN / DELIV / STOCK |
| 3903 | 3903 | PY132C6KM95R | WIP_OPT | Log-exact DEMAN / DELIV / STOCK |

| Report field | SNP source |
|--------------|------------|
| Total Demand | SUM `/SAPAPO/SNPOPDMD-DEMAN` (rolled up to FG + **prod plant**) |
| Total Supply | SUM `/SAPAPO/SNPOPDMN-DELIV` (rolled up to FG + **prod plant**) |
| Opening Stock | `/SAPAPO/SNPOPLMA-STOCK` (FG + **prod plant**) |

Product column remains **FG (`ZFRT`)** via **`SNPOPDMN-MATDL`** mapping (previous fix).

---

## 4. Code corrections

**File:** `WIP2 Substitution/Matbal/ZAPO_MATERIAL_BALANCE_CLS.txt`

### 4.1 `generate_material_balance` — call production qty in WIP path

```abap
IF p_wip_opt = abap_true.
  me->find_mat_prod_plant( ).
  me->calculate_prod_qty( ).    " NEW — same as standard path
ELSE.
  me->calulate_mat_bal_demand( ).
ENDIF.
```

### 4.2 `build_wip_opt_matbal` — aggregate at production plant

**Before:** Key = `FG matnr + log locno (customer) + month`  
**After:** Key = `FG matnr + production plant + month`

Production plant resolution:

```abap
IF gt_loc-loctype = gc_loctyp_plant.
  lv_prod_plant = log_locno.
ELSE.
  " Customer / depot — roll up to gt_mat_prod_plant first plant (e.g. 3903)
  SPLIT gt_mat_prod_plant-plant_list AT ',' INTO lv_prod_plant ...
ENDIF.
```

Apply **`lv_prod_plant`** in all three aggregations (DEMAN, DELIV, STOCK).

### 4.3 Row keys — include all FG materials with production (like PROD_QTY)

```abap
CLEAR lt_row_keys.

" Primary driver: gt_prod_qty output (io_ind O / CO) at plant
LOOP AT gt_prod_qty ... INSERT matnr + prod_plant + month.

" Also merge demand/supply keys
LOOP AT lt_dmd_sum ... INSERT.
LOOP AT lt_supply_sum ... INSERT.
```

This ensures **PY132C6KM95R** appears even when it has **plant production** but no customer IT_DEMAND row.

### 4.4 Extended WIP → FG map from ET_DEMAND

For materials only on ET_DEMAND, map WIP → FG by matching **same locid + matid + bucke** on IT_DEMAND and reading **`MATDL`**.

### 4.5 Display fields

```abap
ls_fin_fields-src_plant    = prod_plant.   " 3903
ls_fin_fields-supply_plant = prod_plant.   " 3903
ls_fin_fields-plant_desc   = HMD - POY- CP 10
ls_fin_fields-added_by_method = 'WIP_OPT'.
```

---

## 5. Change summary

| Area | Change |
|------|--------|
| `generate_material_balance` | Add `calculate_prod_qty` when `p_wip_opt` |
| Aggregation dimension | Customer loc → **production plant** |
| Row keys | **`gt_prod_qty`** + demand/supply sums |
| WIP→FG map | SNPOPDMN + ET/IT match on loc/mat/bucket |
| Output location | Plant **3903**, not ship-to **3000025464** |
| Material count | **Both** PY131C1KC95R and PY132C6KM95R |

---

## 6. Test plan (SAP AD1)

1. T-code **`ZAPO_SNPOP_REPORT`** → Polyester Material Balance → variant **`TEST-MATBAL`**
2. Log `P1005781:001:2026.04.29-20:42:09`, Division **14**
3. Generate with **WIP Optimiser ticked**

| # | Check | Expected |
|---|--------|----------|
| T1 | Row count | **2 rows** (PY131 + PY132) |
| T2 | Plant / Sup Loc | **3903** for both (not 3000025464) |
| T3 | Product | FG codes PY131C1KC95R, PY132C6KM95R |
| T4 | Method | WIP_OPT |
| T5 | Total Demand | = SUM DEMAN from log per FG + plant |
| T6 | Total Supply | = SUM DELIV from log per FG + plant |
| T7 | Opening Stock | = STOCK from ET_LOCMAT at plant |

4. Re-run with WIP **off** — still 2 rows at 3903 (PROD_QTY); quantities may differ (allocation path).

---

## 7. Transport checklist

- [ ] Apply `ZAPO_MATERIAL_BALANCE_CLS.txt` changes
- [ ] Class def: `build_wip_opt_matbal` declared
- [ ] Selection: `p_wip_opt` checkbox
- [ ] Activate and test both screenshots scenario

---

## 8. Related documents

- `Matbal_WIP2_FG_Product_CodeChange.md` — FG product mapping via MATDL  
- `Matbal_WIP_Optimisation_CodeChange.md` — initial WIP log-exact quantities  

---

*End of document.*
