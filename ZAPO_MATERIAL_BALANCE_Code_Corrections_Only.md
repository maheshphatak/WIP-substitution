# ZAPO_MATERIAL_BALANCE — Code corrections only

Apply in include **`ZAPO_MATERIAL_BALANCE_CLS`**. Full analysis, FS, and TS: see **`Matbal_Zero_Qty_Analysis_FS_TS_CodeChange.md`**.

---

## Correction A — `populate_demand_qty`

**Symptom:** `tot_dmd` stays zero when `D_*` has quantity but SNZ ratio branch is skipped (`lv_supply` initial or SNZ/S read fails).

**Change:** Inside the `D_<reg>` branch, after the existing SNZ + `S` ratio `IF ... ENDIF` block, if the ratio was **not** applied, set the output demand component from raw sort demand before the unfulfilled loop.

Refactor the **existing** SNZ / `S` `READ` block (keep current keys and field symbols). After that block completes, set a flag when the ratio line was written, else copy raw demand:

```abap
DATA(lv_dmd_ratio_used) TYPE abap_bool.
CLEAR lv_dmd_ratio_used.

" Keep your current READ SNZ -> <lfs_subtotal> and inner READ 'S' -> <lfs_subtotal_s>.
" When the inner condition is satisfied and you assign <lfs_comp2> from the ratio:
"   lv_dmd_ratio_used = abap_true.

IF lv_dmd_ratio_used = abap_false.
  <lfs_comp2> = <lfs_comp>.
ENDIF.

" Then: unfulfilled customer LOOP, <lfs_comp2> = <lfs_comp2> + lv_unfulfilled_dmd, tot_dmd += <lfs_comp2>
```

---

## Correction B — `populate_other_qty`

**Symptom:** `prod_qty` and `clsg_stk` become zero when `tot_supply + captive_supply` (and `tot_dmd + captive_dmd`) are initial, because code multiplies by `0 / supply_sum`.

**Change:** Only apply the scaling branch when the **numerator** is not initial.

Declare once at start of `populate_other_qty` (method `DATA`):

```abap
DATA: lv_num_sup TYPE p LENGTH 16 DECIMALS 3,
      lv_num_dmd TYPE p LENGTH 16 DECIMALS 3.
```

**`prod_qty` block** (after first `READ TABLE gt_subtot_dmd_src` with `supply_loc = ls_fin_fields-src_plant`):

```abap
IF sy-subrc = 0 AND <lfs_subtotal> IS ASSIGNED.
  lv_num_sup = ls_fin_qty-tot_supply + ls_fin_qty-captive_supply.
  lv_num_dmd = ls_fin_qty-tot_dmd + ls_fin_qty-captive_dmd.

  IF <lfs_subtotal>-supply_sum IS NOT INITIAL AND lv_num_sup IS NOT INITIAL.
    ls_fin_qty-prod_qty = ls_fin_qty-prod_qty * lv_num_sup / <lfs_subtotal>-supply_sum.
  ELSEIF <lfs_subtotal>-dmd_sum IS NOT INITIAL AND lv_num_dmd IS NOT INITIAL.
    ls_fin_qty-prod_qty = ls_fin_qty-prod_qty * lv_num_dmd / <lfs_subtotal>-dmd_sum.
  ELSEIF <lfs_subtotal>-lane_count IS NOT INITIAL.
    ls_fin_qty-prod_qty = ls_fin_qty-prod_qty / <lfs_subtotal>-lane_count.
  ENDIF.
ENDIF.
```

**`clsg_stk` block** (after `READ TABLE gt_subtot_dmd_supply`): reuse `lv_num_sup` / `lv_num_dmd`:

```abap
IF sy-subrc = 0 AND <lfs_subtotal> IS ASSIGNED.
  lv_num_sup = ls_fin_qty-tot_supply + ls_fin_qty-captive_supply.
  lv_num_dmd = ls_fin_qty-tot_dmd + ls_fin_qty-captive_dmd.

  IF <lfs_subtotal>-supply_sum IS NOT INITIAL AND lv_num_sup IS NOT INITIAL.
    ls_fin_qty-clsg_stk = ls_fin_qty-clsg_stk * lv_num_sup / <lfs_subtotal>-supply_sum.
  ELSEIF <lfs_subtotal>-dmd_sum IS NOT INITIAL AND lv_num_dmd IS NOT INITIAL.
    ls_fin_qty-clsg_stk = ls_fin_qty-clsg_stk * lv_num_dmd / <lfs_subtotal>-dmd_sum.
  ENDIF.
ENDIF.
```

---

## Correction C — `append_to_outtab_dyn` (existing row branch)

**Change:** After assigning `CUSTOMER` to `<lfs_comp_tab>`, guard with the correct field symbol:

```abap
ASSIGN COMPONENT 'CUSTOMER' OF STRUCTURE <lfs_final> TO <lfs_comp_tab>.
IF <lfs_comp_tab> IS ASSIGNED.
```

Replace the erroneous `IF <lfs_comp> IS ASSIGNED.` for that block.

---

*End of code-only corrections.*
