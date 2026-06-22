# Material Balance — WIP2 Optimisation: FG Product + Log-Exact Quantities

**Program:** `ZAPO_SNPOP_REPORT` → `ZAPO_MATERIAL_BALANCE`  
**Include:** `ZAPO_MATERIAL_BALANCE_CLS`  
**Variant:** `TEST-MATBAL`  
**Report type:** Polyester Material Balance  
**Test log:** `P1005781:001:2026.04.29-20:42:09` (Division 14)

---

## 1. Observed behaviour (before fix)

| Setting | Product column | Total Demand / Supply / Opening Stock |
|---------|----------------|----------------------------------------|
| **WIP2 Optimisation OFF** | Correct **FG** (`ZFRT` / Material Type FG) | **Wrong** — regional proration, lane splits, ratio scaling in `populate_supply` / `populate_demand_qty` / `populate_other_qty` |
| **WIP2 Optimisation ON** (first WIP path) | **Wrong** — shows **ZWIP** product codes | Quantities from log were closer but keyed on WIP `matid`, not FG |

### Root cause — wrong product (WIP2 ON)

1. Previous fix added **`ZWIP`** to ECC material selection (`fill_selection_matnr`).
2. `build_wip_opt_matbal` used **log `matid`** directly as report `MATNR`.
3. In WIP2 optimizer runs, SNP log lines use **WIP product on `matid`** and **FG deliverable on `matdl`** (`/SAPAPO/SNPOPDMN`), same pattern as Contribution report.

### Root cause — wrong quantities (WIP2 OFF)

Standard path derives totals through allocation logic; they are **not** 1:1 with SNP log sums.

---

## 2. Expected behaviour (after fix)

When **WIP2 Optimisation** is checked:

| Report field | SNP source | Table / field | Rule |
|--------------|------------|---------------|------|
| **Product Number** | FG finished goods | ECC `MARA-MTART = ZFRT` | Display FG from **`SNPOPDMN-MATDL`** when `MATID ≠ MATDL` |
| **Total Demand** | ET_DEMAND | `/SAPAPO/SNPOPDMD-DEMAN` | SUM all buckets, rolled up to **FG** |
| **Opening Stock** | ET_LOCMAT | `/SAPAPO/SNPOPLMA-STOCK` | Per FG + location (sum WIP stocks mapped to FG) |
| **Total Supply** | IT_DEMAND | `/SAPAPO/SNPOPDMN-DELIV` | SUM all buckets, rolled up to **FG** |

When **WIP2 Optimisation** is **unchecked**: existing standard FG path is unchanged (FG products, allocated quantities).

---

## 3. Design

### 3.1 WIP2 ON — dedicated path (unchanged entry points)

```
generate_material_balance
  IF p_wip_opt = abap_true
    find_mat_prod_plant( )          " skip intermediate demand calc
    build_wip_opt_matbal( )         " NEW logic below
  ELSE
    calulate_mat_bal_demand( )
    populate_supply → populate_demand_qty → populate_other_qty
  ENDIF
```

### 3.2 FG resolution (NEW)

```
Step 1: lt_matid_matnr  ← SELECT /SAPAPO/MATKEY for all SNPOPMAT (full log, not ECC-filtered)

Step 2: lt_wip_fg_map   ← FROM /SAPAPO/SNPOPDMN
         log_matnr = MATNR(MATID)
         IF MATDL ≠ MATID AND MATDL is initialised
           fg_matnr = MATNR(MATDL)    " FG deliverable
         ELSE
           fg_matnr = log_matnr

Step 3: Aggregate DEMAN, DELIV, STOCK using fg_matnr + locno + month

Step 4: Output rows only where fg_matnr ∈ gt_ecc_mat_master (ZFRT only)
```

### 3.3 ECC material fetch (REVERTED)

- **`fill_selection_matnr`**: keep **`ZFRT` only** — do **not** add `ZWIP`.
- Log quantities still read from SNP tables for all materials; only **display** is FG.

### 3.4 Region columns

- `create_dyn_tab`: when `p_wip_opt AND r_gen` → region list = **`OTHR` only** (totals, no regional split).

---

## 4. Code changes

**File:** `WIP2 Substitution/Matbal/ZAPO_MATERIAL_BALANCE_CLS.txt`

### 4.1 Remove ZWIP from `fill_selection_matnr`

```abap
" Material Type — ZFRT only (FG). WIP log materials mapped to FG in build_wip_opt_matbal.
<lfs_selopt>-low = 'ZFRT'.
" REMOVED: ZWIP append when p_wip_opt
```

### 4.2 `build_wip_opt_matbal` — key additions

1. **`lt_matid_matnr`** — full log matid→matnr (avoids broken lookup after ECC clears non-ZFRT `gt_matkey-matid`).
2. **`lt_wip_fg_map`** — WIP log product → FG from `SNPOPDMN-MATDL`.
3. All three aggregations (DEMAN, DELIV, STOCK) use **FG matnr** as key.
4. Opening stock: **`+=`** when multiple WIP lines map to same FG+location.
5. Output: **`gt_ecc_mat_master`** filter → FG products only.

Search anchor: `METHOD build_wip_opt_matbal`.

### 4.3 SAP prerequisites (manual)

| Object | Action |
|--------|--------|
| Selection screen | `p_wip_opt` checkbox (WIP2 Optimisation) |
| Class definition | `METHODS build_wip_opt_matbal.` |
| Text symbol 091 | Optional progress text |

---

## 5. Validation — SAP AD1

**MCP note:** AD1 MCP was **not connected** in the development session (`No MCP servers available`). Validate manually in SAP GUI.

### 5.1 Execute report

1. T-code **`ZAPO_SNPOP_REPORT`**
2. SNP Optimizer reports → **Polyester Material Balance**
3. Variant **`TEST-MATBAL`**
4. Optimizer run: `P1005781:001:2026.04.29-20:42:09`, Division `14`

### 5.2 Compare WIP2 OFF vs ON

| Check | WIP2 OFF | WIP2 ON (after fix) |
|-------|----------|---------------------|
| Product type | FG (`ZFRT`) | FG (`ZFRT`) — **not ZWIP** |
| Sample product | e.g. `PY131C1KC95R` | Same FG code |
| Total Demand | May differ from log | = SUM `SNPOPDMD-DEMAN` for FG |
| Total Supply | May differ from log | = SUM `SNPOPDMN-DELIV` for FG |
| Opening Stock | Scaled / wrong | = SUM `SNPOPLMA-STOCK` mapped to FG |

### 5.3 Reference SQL (SE16 / SQVI)

**FG mapping check (IT_DEMAND):**

```sql
SELECT m.matnr AS log_product, m2.matnr AS fg_product, COUNT(*) AS lines
  FROM /SAPAPO/SNPOPDMN d
  JOIN /SAPAPO/MATKEY m  ON d.matid = m.matid
  JOIN /SAPAPO/MATKEY m2 ON d.matdl = m2.matid
 WHERE d.sessionid = '<snpsession>'
   AND d.matid <> d.matdl
 GROUP BY m.matnr, m2.matnr
```

**Total Demand for FG product:**

```sql
SELECT m2.matnr, l.locno, SUM(d.deman) AS tot_dmd
  FROM /SAPAPO/SNPOPDMD d
  JOIN /SAPAPO/MATKEY m  ON d.matid = m.matid
  JOIN /SAPAPO/SNPOPDMN n ON d.sessionid = n.sessionid
                           AND d.locid = n.locid
                           AND d.matid = n.matid
                           AND d.bucke = n.bucke
  JOIN /SAPAPO/MATKEY m2 ON n.matdl = m2.matid
  JOIN /SAPAPO/LOC l ON d.locid = l.locid
 WHERE d.sessionid = '<snpsession>'
 GROUP BY m2.matnr, l.locno
```

**Persisted report:**

```sql
SELECT matnr, scr_plant, cal_month, tota_demand, total_supply, opng_stk
  FROM zapo_matbal_hrd
 WHERE sessionname = 'P1005781:001:2026.04.29-20:42:09'
   AND div = '14'
 ORDER BY matnr, cal_month
```

---

## 6. Transport checklist

- [ ] Apply `ZAPO_MATERIAL_BALANCE_CLS.txt` changes to SAP include
- [ ] Class definition: `build_wip_opt_matbal` declared
- [ ] Activate program + includes
- [ ] Generate with **WIP2 ON** → confirm FG products + log-matching totals
- [ ] Generate with **WIP2 OFF** → confirm FG products (quantities unchanged vs pre-fix standard path)
- [ ] Display variant `TEST-MATBAL` → data visible in ALV

---

## 7. Related documents

| Document | Topic |
|----------|-------|
| `Matbal_WIP_Optimisation_CodeChange.md` | Initial WIP path + log table mapping |
| `ZAPO_CONTRIBUTION_BOM_ND_Penalty_Substitution_Gap.md` | `matid` / `matdl` substitution pattern |
| `ZAPO_MATERIAL_BALANCE_Implementation_CodeChange.md` | TEST-MATBAL mock guard + PROD_QTY fixes |

---

*End of document.*
