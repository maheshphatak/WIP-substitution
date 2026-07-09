# Material Balance — WIP Optimisation + Display Mode Fix

**Program:** `ZAPO_MATERIAL_BALANCE`  
**Include:** `ZAPO_MATERIAL_BALANCE_CLS`  
**System:** DEVSCMAD1 (AD1) — **confirmed via live source fetch (Jul 2026)**  
**Checkbox parameter:** `c_wip` (selection screen)  
**Transport status:** Error block **still present on AD1** until §3.1 is applied in SAP.

---

## 1. Error (screenshot)

| Selection | Value |
|-----------|--------|
| Execution mode | **Display Material Balance** |
| Optimizer run | `P1005781:001:2026.04.29-20:42:09` |
| Division | `14` |
| **WIP Optimization** | **Checked** |

**Message:** `WIP Optimisation is valid only for Generate` (text **092**)

---

## 2. Root cause (confirmed on AD1)

In `validate_screen` on AD1, this block exists:

```abap
IF c_wip = abap_true AND r_gen IS INITIAL.
  MESSAGE 'WIP Optimisation is valid only for Generate'(092)
    TYPE 'E'.
ENDIF.
```

`r_gen IS INITIAL` means **Display** or **Delete** — so Display with WIP checkbox is blocked before `START-OF-SELECTION`.

**Intended flow:**

| Step | Mode | WIP checkbox | Action |
|------|------|--------------|--------|
| 1 | Generate | ON | `build_wip_opt_matbal` → save `ZAPO_MATBAL_HRD` / `ITEM` |
| 2 | Display | ON | `fetch_ztable_data` → ALV (same data as Generate) |

FG path (WIP **unchecked**) is unchanged — still uses standard generate/display logic.

---

## 3. Code corrections

### 3.1 `validate_screen` — **DELETE blocking IF** (mandatory)

**Remove entirely** from `ZAPO_MATERIAL_BALANCE_CLS` on AD1:

```abap
IF c_wip = abap_true AND r_gen IS INITIAL.
  MESSAGE 'WIP Optimisation is valid only for Generate'(092)
    TYPE 'E'.
ENDIF.
```

No replacement needed. Display with `c_wip` must pass validation like FG Display.

### 3.2 `create_dyn_tab` — OTHR layout for Display + WIP

WIP rows use **OTHR** totals only. On AD1 today:

```abap
IF c_wip = abap_true AND r_gen = abap_true.   " ← blocks Display layout
```

**Change to:**

```abap
IF c_wip = abap_true.
  CLEAR lt_reg_off.
  APPEND gc_reg_othr TO lt_reg_off.
ENDIF.
```

**FG impact:** None — block runs only when `c_wip` is checked.

### 3.3 `fetch_ztable_data` — allow Display when ITEM empty

After WIP Generate, allow Display from header if item rows missing:

```abap
IF sy-subrc <> 0.
  IF c_wip = abap_true AND r_disp IS NOT INITIAL.
    CLEAR gt_matbal_item.
  ELSE.
    MESSAGE 'No Data Found'(037) TYPE 'S' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.
ENDIF.
```

**FG impact:** None — only when `c_wip AND r_disp`.

### 3.4 `process_material_balance` — show WIP_OPT on Display

When Display with WIP checkbox, set method on ALV rows:

```abap
IF c_wip = abap_true.
  ls_fin_fields-added_by_method = gc_wip_method.   " 'WIP_OPT'
ENDIF.
```

Apply in both loops (item-driven and header-only paths).

**FG impact:** None — only when `c_wip` checked.

### 3.5 Generate path (unchanged behaviour)

WIP Generate on AD1 already uses:

```abap
IF c_wip = abap_true.
  me->find_mat_prod_plant( ).
  me->calculate_prod_qty( ).
  me->create_dyn_tab( ).
  me->build_wip_opt_matbal( ).
ELSE.
  me->calulate_mat_bal_demand( ).
  ...
ENDIF.
```

Persist via `append_for_db_upd_wip` (OTHR item fallback already in AD1 code).

---

## 4. FG vs WIP — isolation summary

| Area | FG (c_wip = OFF) | WIP (c_wip = ON) |
|------|------------------|------------------|
| `validate_screen` | Unchanged | Remove error 092 block only |
| `generate_material_balance` | Standard path | `build_wip_opt_matbal` only |
| `create_dyn_tab` | Regional columns from PB/ITEM | Force `gc_reg_othr` only |
| `fetch_ztable_data` | Existing ITEM required | Optional ITEM clear on Display |
| `process_material_balance` | No `gc_wip_method` set | Set `WIP_OPT` on display rows |
| Display output | From `ZAPO_MATBAL_*` | Same tables, OTHR layout |

---

## 5. Test plan (AD1)

### Prerequisites

Generate once with **WIP Optimization ON** for `P1005781:001:2026.04.29-20:42:09`, Division `14`.

### Test 1 — WIP Display (fix target)

1. **Display Material Balance**
2. **WIP Optimization** checked
3. Same run + division  
4. **Expected:** No error 092; ALV matches last WIP Generate (FG products, plant 3903, totals, `WIP_OPT`)

### Test 2 — FG regression (must not break)

| # | Mode | WIP | Expected |
|---|------|-----|----------|
| R1 | Generate | OFF | FG products, regional columns, same as before |
| R2 | Display | OFF | Shows prior FG generate; no error |
| R3 | Generate | ON | WIP generate unchanged |
| R4 | Display | OFF after WIP generate | Shows data (may differ in layout — acceptable) |

---

## 6. Transport checklist

- [ ] AD1: Delete `validate_screen` IF block (§3.1) — **fixes error 092**
- [ ] Apply `create_dyn_tab` change (§3.2)
- [ ] Apply `fetch_ztable_data` change (§3.3)
- [ ] Apply `process_material_balance` change (§3.4)
- [ ] Activate `ZAPO_MATERIAL_BALANCE` + includes
- [ ] Run tests §5

**Workspace file:** `WIP2 Substitution/Matbal/ZAPO_MATERIAL_BALANCE_CLS.txt` (aligned to `c_wip` / `gc_wip_method` / `gc_reg_othr` from AD1 TOP)

### Quick apply order on AD1

1. **SE38** → `ZAPO_MATERIAL_BALANCE_CLS` → `validate_screen` → delete lines with `092` (§3.1) — **this removes the screenshot error**
2. `create_dyn_tab` → §3.2
3. `fetch_ztable_data` → §3.3
4. `process_material_balance` → §3.4 (two loops)
5. Activate and test §5

---

## 7. Related documents

- `Matbal_WIP2_Both_Materials_Plant_CodeChange.md` — both FG materials at plant on WIP Generate
- `Matbal_WIP2_FG_Product_CodeChange.md` — FG product via MATDL mapping

---

*End of document.*
