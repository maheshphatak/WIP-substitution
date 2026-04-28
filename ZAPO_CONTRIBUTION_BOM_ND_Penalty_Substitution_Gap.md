# Contribution and BOM Report — ND Penalty vs Substitution Material (Gap Analysis)

**Object:** Include `ZAPO_CONTRIBUTION_BOM_CLS` (retrieved from SAP via ADT/MCP `sap_mcp_ad1`)  
**Symptom:** ND Penalty reflects **Product ID** (`matid` from demand header) instead of **Substitution Material** (`matdl` on deliverable line in `SNPOPDMN`).  
**Date:** 2026-04-28  

---

## 1. Data model (relevant SNP log tables)

| Table | Role |
|--------|------|
| `/SAPAPO/SNPOPDMD` | ET demand — location, product `matid`, bucket `bucke`, forecast `deman` (no substitution / deliverable split on this structure in your fetch). |
| `/SAPAPO/SNPOPDMN` | IT demand / supply — includes `matid` (product in substitution context) and **`matdl`** (deliverable / substitution material). |
| `/SAPAPO/SNPOPDCT` | Demand classes incl. **ND penalty** (`ndpen`) — keyed by session, `locid`, **`matid`**, `bckto`, etc. |

For product substitution, SNP typically associates demand-class / ND penalty with the **material that is actually planned/delivered** (the substitution / deliverable), i.e. the `matid` that appears on `SNPOPDCT` for that scenario matches **`matdl`** (when `matid` ≠ `matdl`), not the original product `matid` on the `SNPOPDMN` line.

---

## 2. What the code does today

### 2.1 Contribution lines correctly expose substitution on the output

In `populate_contribution`, `matnr` (product) and `matnr_sub` (substitution) are set from the **IT** line (`SNPOPDMN`):

- `matnr` ← `get_guid_desc( <lfs_it_dmd>-matid )`
- If `matid = matdl` → `matnr_sub` = `matnr`
- Else → `matnr_sub` ← `get_guid_desc( <lfs_it_dmd>-matdl )`

So the **display / downstream** side already distinguishes Product ID vs Substitution Material.

### 2.2 ND penalty is still read with the product `matid`

`set_mou_ndpen_qty` loads ND penalty from internal table `gt_snpopdct` (filled from `/SAPAPO/SNPOPDCT`), sorted by `locid matid bckto`, with:

```abap
READ TABLE gt_snpopdct ASSIGNING <lfs_dct>
  WITH KEY
    locid = is_dmd-locid
    matid = is_dmd-matid
    bckto = <lfs_bucket>-bucke
  BINARY SEARCH.
```

`populate_contribution` passes:

```abap
is_dmd = ls_et_demand   " TYPE gty_snpopdmd — from SNPOPDMD
```

`ls_et_demand` is read from `gt_snpopdmd` with key `locid`, `matid`, `bucke` matching `<lfs_it_dmd>` from `SNPOPDMN` — so **`is_dmd-matid` is always the product** from the ET row. The **substitution material `matdl` from the current `SNPOPDMN` line is never passed** into `set_mou_ndpen_qty`.

**Result:** For substitution, the READ uses the **product** GUID as `matid`. If `SNPOPDCT` holds ND penalty for the **deliverable** material, the READ either hits the wrong row (product) or fails and leaves wrong / stale values — which matches the reported behaviour (ND Penalty tied to Product ID instead of Substitution Material).

### 2.3 MOU branch (same method)

`gt_snpopcli` is also read with `matid = is_dmd-matid`. If MOU is maintained on the deliverable material in your process, the same class of issue may exist for MOU; this note focuses on ND penalty as requested.

---

## 3. Root cause (summary)

| Area | Issue |
|------|--------|
| **Lookup key** | `set_mou_ndpen_qty` uses `is_dmd-matid` from `SNPOPDMD` only. |
| **Substitution** | Relevant SNP key for ND penalty should align with **`matdl`** when `matid` ≠ `matdl` on `SNPOPDMN`. |
| **Gap** | Product vs substitution is applied for `matnr` / `matnr_sub`, but **not** for the `SNPOPDCT` lookup. |

---

## 4. Proposed correction

### 4.1 Principle

For the ND penalty `READ` on `gt_snpopdct`, use:

- **`matdl`** from the current `SNPOPDMN` line when **`matid` ≠ `matdl`** (and `matdl` is initialised),
- otherwise **`matid`**.

Keep using `is_dmd` for **location** and bucket alignment as today (still sourced from the ET demand row for `bucke` / `locid`).

### 4.2 Interface change (recommended)

Extend `set_mou_ndpen_qty` with an optional importing parameter used **only** for the `gt_snpopdct` key (and optionally for MOU later if business confirms):

```abap
METHODS set_mou_ndpen_qty
  IMPORTING
    is_dmd             TYPE gty_snpopdmd   " unchanged — locid, bucke context from ET
    iv_matid_for_ndpen TYPE /sapapo/matid OPTIONAL  " NEW: DCT lookup material
  CHANGING
    cs_contri          TYPE zapo_snp_dmdvsup.
```

Inside `set_mou_ndpen_qty`, before the `LOOP AT gt_buckets` / `READ TABLE gt_snpopdct`:

```abap
DATA(lv_dct_matid) TYPE /sapapo/matid.
IF iv_matid_for_ndpen IS SUPPLIED.
  lv_dct_matid = iv_matid_for_ndpen.
ELSE.
  lv_dct_matid = is_dmd-matid.
ENDIF.
```

Replace the `READ TABLE gt_snpopdct` key:

```abap
READ TABLE gt_snpopdct ASSIGNING <lfs_dct>
  WITH KEY
    locid = is_dmd-locid
    matid = lv_dct_matid
    bckto = <lfs_bucket>-bucke
  BINARY SEARCH.
```

Leave **`gt_snpopcli`** read on `is_dmd-matid` unless functional owners confirm MOU is also on deliverable material.

### 4.3 Caller change in `populate_contribution`

Immediately before `set_mou_ndpen_qty`:

```abap
DATA(lv_matid_ndpen) TYPE /sapapo/matid.

IF <lfs_it_dmd>-matid <> <lfs_it_dmd>-matdl AND <lfs_it_dmd>-matdl IS NOT INITIAL.
  lv_matid_ndpen = <lfs_it_dmd>-matdl.
ELSE.
  lv_matid_ndpen = <lfs_it_dmd>-matid.
ENDIF.

me->set_mou_ndpen_qty(
  EXPORTING
    is_dmd             = ls_et_demand
    iv_matid_for_ndpen = lv_matid_ndpen
  CHANGING
    cs_contri          = ls_contribution
).
```

**Note:** `ls_et_demand` can still be used for `is_dmd`; only the DCT material key changes to `lv_matid_ndpen`.

### 4.4 Other callers

- **`populate_not_deliv_contri`:** passes `<lfs_et_dmd>` from `gt_snpopdmd` only; there `matnr_sub` equals `matnr` (no split). **Omit** `iv_matid_for_ndpen` so behaviour stays `is_dmd-matid` (default path).
- Search the class for any other `set_mou_ndpen_qty` calls and apply the same pattern wherever the source row is `gty_snpopdmn` with possible substitution.

### 4.5 Regression / test hints

1. **No substitution:** `matid = matdl` → ND penalty unchanged vs today.  
2. **Substitution:** `matid` ≠ `matdl` → ND penalty should match `SNPOPDCT` row for deliverable `matdl` (verify in SNP log / SE16 for same session, loc, bucket).  
3. **Captive / `gw_flag` path:** ND penalty from `gt_raw_mat_trf_cost` uses `cs_contri-matnr`; validate separately if that should use `matnr_sub` for substitution (out of scope unless the same symptom appears there).

---

## 5. Traceability

| Item | Detail |
|------|--------|
| Include | `ZAPO_CONTRIBUTION_BOM_CLS` |
| Method | `set_mou_ndpen_qty` |
| Caller | `populate_contribution` (primary gap) |
| Tables | `/SAPAPO/SNPOPDCT` → `gt_snpopdct`; demand line `/SAPAPO/SNPOPDMN` (`matdl`) |

---

*Analysis based on live source retrieved from SAP system connected to MCP server `sap_mcp_ad1`.*
