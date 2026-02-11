# Code Correction: ZPSHP Table Update Issue - ZEXMATNR and ZEXDESC Fields
## Product: PY1522809R | Ship to Party: 3000026743

---

## 1. Problem Statement

**Issue:** Product 'PY1522809R' for Ship to Party '3000026743' is not being updated in Table 'ZPSHP' when running program `ZAPO_PTC_SUBSTITUTION` with variant `TEST_SUBST`. Specifically, fields `ZEXMATNR` and `ZEXDESC` from table `ZAPO_PTC_SUBST` are not being populated in `ZPSHP` table.

**Program:** `ZAPO_PTC_SUBSTITUTION`  
**Function Module:** `ZAPO_ZPSHP_MODIFY`  
**Transaction:** `ZSUBST`  
**Variant:** `TEST_SUBST`  
**Source Table:** `ZAPO_PTC_SUBST`  
**Target Table:** `ZPSHP` (Structure: `ZPAPOSHP`)  
**Missing Fields:** `ZEXMATNR`, `ZEXDESC`

---

## 2. Program Flow Analysis

### 2.1 Execution Flow for Category 1 + Category 10

```abap
IF ( p_cat1 = abap_true ) AND ( p_cat10 = abap_true ).
  go_obj->updating_stageing_tables( ).
  go_obj->create_loc_and_extend_pcat11( CHANGING ct_excel = gt_sub1 ).
  go_obj->user_activity_bapi( ).
ENDIF.
```

**Key Methods:**
1. `updating_stageing_tables()` - Updates staging tables from `ZAPO_PTC_SUBST`
2. `create_loc_and_extend_pcat11()` - Creates locations and extends products to ship-to-parties (likely where ZPSHP is populated)
3. `user_activity_bapi()` - Processes BAPI calls for substitution data

### 2.2 Expected Data Flow

```
ZAPO_PTC_SUBST (Source)
    ↓
GT_SUB1 (Internal Table)
    ↓
create_loc_and_extend_pcat11()
    ↓
ZAPO_ZPSHP_MODIFY (Function Module)
    ↓
ZPSHP (Target Table)
```

---

## 3. Root Cause Analysis

### 3.1 Primary Issue: Missing Field Mapping

**Problem:** The code is not properly mapping `ZEXMATNR` and `ZEXDESC` fields from `ZAPO_PTC_SUBST` table to `ZPSHP` table during the update process.

**Possible Root Causes:**

1. **Missing Field Assignment in `create_loc_and_extend_pcat11`**
   - Fields `ZEXMATNR` and `ZEXDESC` are not being read from `ZAPO_PTC_SUBST` table
   - Fields are not being passed to `ZAPO_ZPSHP_MODIFY` function module
   - Fields are not being assigned to ZPSHP work area before MODIFY/INSERT

2. **Missing Field Mapping in `ZAPO_ZPSHP_MODIFY`**
   - Function module `ZAPO_ZPSHP_MODIFY` may not be receiving `ZEXMATNR` and `ZEXDESC` as input parameters
   - Function module may not be assigning these fields to ZPSHP structure before update

3. **Data Not Available in Source**
   - `ZEXMATNR` and `ZEXDESC` may not exist in `ZAPO_PTC_SUBST` for the specific product/ship-to-party combination
   - Data may be filtered out before reaching the update logic

4. **Conditional Logic Skipping Update**
   - Update logic may have conditions that exclude records where `ZEXMATNR` or `ZEXDESC` are initial
   - Location/product validation may be failing, preventing ZPSHP update

5. **Field Name Mismatch**
   - Field names in code may not match actual table structure
   - Conversion issues between source and target field names

---

## 4. Code Corrections

### 4.1 Correction 1: Enhance `create_loc_and_extend_pcat11` to Read and Pass ZEXMATNR and ZEXDESC

**Location:** Method `create_loc_and_extend_pcat11` in class `LCL_MASTER_DATA_SUBSTITUTION`

**Issue:** The method needs to read `ZEXMATNR` and `ZEXDESC` from `ZAPO_PTC_SUBST` table and ensure they are passed to the ZPSHP update logic.

```abap
METHOD create_loc_and_extend_pcat11.
  
  " ============================================================
  " CORRECTED: Read ZEXMATNR and ZEXDESC from ZAPO_PTC_SUBST
  " ============================================================
  DATA: 
    lt_zapo_ptc_subst TYPE STANDARD TABLE OF zapo_ptc_subst,
    lw_zapo_ptc_subst TYPE zapo_ptc_subst,
    lv_zexmatnr TYPE matnr,
    lv_zexdesc TYPE string.
  
  " Read substitution data for all products in input
  SELECT * FROM zapo_ptc_subst
    INTO TABLE lt_zapo_ptc_subst
    FOR ALL ENTRIES IN ct_excel
    WHERE zexmatnr = ct_excel-zexmatnr
       OR zldmatnr = ct_excel-zexmatnr.
  
  " Process each record in ct_excel
  LOOP AT ct_excel ASSIGNING FIELD-SYMBOL(<ls_excel>).
    
    CLEAR: lv_zexmatnr, lv_zexdesc, lw_zapo_ptc_subst.
    
    " ============================================================
    " NEW: Read ZEXMATNR and ZEXDESC from ZAPO_PTC_SUBST
    " ============================================================
    " Try to find matching record in ZAPO_PTC_SUBST
    READ TABLE lt_zapo_ptc_subst INTO lw_zapo_ptc_subst
      WITH KEY zexmatnr = <ls_excel>-zexmatnr.
    
    IF sy-subrc <> 0.
      " Try with zldmatnr if zexmatnr not found
      READ TABLE lt_zapo_ptc_subst INTO lw_zapo_ptc_subst
        WITH KEY zldmatnr = <ls_excel>-zexmatnr.
    ENDIF.
    
    IF sy-subrc = 0.
      " Found matching record - extract ZEXMATNR and ZEXDESC
      lv_zexmatnr = lw_zapo_ptc_subst-zexmatnr.
      lv_zexdesc = lw_zapo_ptc_subst-zexdesc.
      
      " Store in excel structure for later use
      <ls_excel>-zexmatnr = lv_zexmatnr.
      <ls_excel>-zexdesc = lv_zexdesc.
    ELSE.
      " If not found in ZAPO_PTC_SUBST, use values from ct_excel
      lv_zexmatnr = <ls_excel>-zexmatnr.
      lv_zexdesc = <ls_excel>-zexdesc.
      
      " Log warning if data not found
      IF <ls_excel>-zexmatnr = 'PY1522809R' AND
         <ls_excel>-zshptp = '3000026743'.
        MESSAGE w001(zapo_subst) WITH 
          'ZEXMATNR/ZEXDESC not found in ZAPO_PTC_SUBST for'
          <ls_excel>-zexmatnr <ls_excel>-zshptp.
      ENDIF.
    ENDIF.
    
    " ============================================================
    " Continue with existing location creation logic...
    " ============================================================
    " (Location creation code remains the same)
    
    " ============================================================
    " CRITICAL: Update ZPSHP with ZEXMATNR and ZEXDESC
    " ============================================================
    IF <ls_excel>-locid IS NOT INITIAL.
      
      " Call function module to update ZPSHP
      CALL FUNCTION 'ZAPO_ZPSHP_MODIFY'
        EXPORTING
          iv_matnr     = <ls_excel>-zexmatnr
          iv_shptp     = <ls_excel>-zshptp
          iv_locid     = <ls_excel>-locid
          iv_zexmatnr  = lv_zexmatnr      " NEW: Pass ZEXMATNR
          iv_zexdesc   = lv_zexdesc       " NEW: Pass ZEXDESC
        EXCEPTIONS
          error        = 1
          OTHERS       = 2.
      
      IF sy-subrc <> 0.
        " Error in ZPSHP update
        MESSAGE e002(zapo_subst) WITH 
          'ZPSHP update failed for' <ls_excel>-zexmatnr <ls_excel>-zshptp.
      ELSE.
        " Success - verify update for specific product
        IF <ls_excel>-zexmatnr = 'PY1522809R' AND
           <ls_excel>-zshptp = '3000026743'.
          MESSAGE i003(zapo_subst) WITH 
            'ZPSHP updated successfully for PY1522809R / 3000026743'.
        ENDIF.
      ENDIF.
    ENDIF.
    
  ENDLOOP.
  
ENDMETHOD.
```

---

### 4.2 Correction 2: Update Function Module `ZAPO_ZPSHP_MODIFY` to Accept and Update ZEXMATNR and ZEXDESC

**Location:** Function Module `ZAPO_ZPSHP_MODIFY`

**Issue:** Function module needs to accept `ZEXMATNR` and `ZEXDESC` as input parameters and update them in ZPSHP table.

```abap
FUNCTION ZAPO_ZPSHP_MODIFY.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_MATNR) TYPE MATNR
*"     VALUE(IV_SHPTP) TYPE /SAPAPO/LOCNO
*"     VALUE(IV_LOCID) TYPE /SAPAPO/LOCID
*"     VALUE(IV_ZEXMATNR) TYPE MATNR          " NEW: Add parameter
*"     VALUE(IV_ZEXDESC) TYPE STRING           " NEW: Add parameter
*"  EXCEPTIONS
*"     ERROR
*"----------------------------------------------------------------------

  DATA: 
    lw_zpshp TYPE zpshp,
    lw_zpshp_existing TYPE zpshp.
  
  " ============================================================
  " CORRECTED: Check if record exists in ZPSHP
  " ============================================================
  SELECT SINGLE * FROM zpshp
    INTO lw_zpshp_existing
    WHERE matnr = iv_matnr
      AND shptp = iv_shptp.
  
  IF sy-subrc = 0.
    " Record exists - update it
    lw_zpshp = lw_zpshp_existing.
    
    " Update fields
    lw_zpshp-locid = iv_locid.
    lw_zpshp-zexmatnr = iv_zexmatnr.      " NEW: Update ZEXMATNR
    lw_zpshp-zexdesc = iv_zexdesc.        " NEW: Update ZEXDESC
    lw_zpshp-aedat = sy-datum.
    lw_zpshp-aezet = sy-uzeit.
    lw_zpshp-aenam = sy-uname.
    
    MODIFY zpshp FROM lw_zpshp.
    
    IF sy-subrc <> 0.
      MESSAGE e001(zapo_subst) WITH 
        'Error updating ZPSHP for' iv_matnr iv_shptp.
      RAISE error.
    ENDIF.
    
  ELSE.
    " Record does not exist - insert new
    CLEAR lw_zpshp.
    lw_zpshp-matnr = iv_matnr.
    lw_zpshp-shptp = iv_shptp.
    lw_zpshp-locid = iv_locid.
    lw_zpshp-zexmatnr = iv_zexmatnr.      " NEW: Set ZEXMATNR
    lw_zpshp-zexdesc = iv_zexdesc.        " NEW: Set ZEXDESC
    lw_zpshp-erdat = sy-datum.
    lw_zpshp-erzet = sy-uzeit.
    lw_zpshp-ernam = sy-uname.
    
    INSERT zpshp FROM lw_zpshp.
    
    IF sy-subrc <> 0.
      MESSAGE e002(zapo_subst) WITH 
        'Error inserting ZPSHP for' iv_matnr iv_shptp.
      RAISE error.
    ENDIF.
  ENDIF.
  
  " Commit the changes
  COMMIT WORK.
  
ENDFUNCTION.
```

---

### 4.3 Correction 3: Ensure Data is Read from ZAPO_PTC_SUBST in `updating_stageing_tables`

**Location:** Method `updating_stageing_tables` in class `LCL_MASTER_DATA_SUBSTITUTION`

**Issue:** Ensure that `ZEXMATNR` and `ZEXDESC` are properly read from `ZAPO_PTC_SUBST` and populated in `GT_SUB1` internal table.

```abap
METHOD updating_stageing_tables.
  
  " ============================================================
  " CORRECTED: Read ZEXMATNR and ZEXDESC from ZAPO_PTC_SUBST
  " ============================================================
  DATA: 
    lt_zapo_ptc_subst TYPE STANDARD TABLE OF zapo_ptc_subst,
    lw_zapo_ptc_subst TYPE zapo_ptc_subst.
  
  " Read all relevant records from ZAPO_PTC_SUBST
  SELECT * FROM zapo_ptc_subst
    INTO TABLE lt_zapo_ptc_subst
    WHERE zldmatnr IN s_matnr[]
       OR zexmatnr IN s_matnr[].
  
  " Update GT_SUB1 with ZEXMATNR and ZEXDESC from ZAPO_PTC_SUBST
  LOOP AT gt_sub1 ASSIGNING FIELD-SYMBOL(<ls_sub1>).
    
    " Find matching record in ZAPO_PTC_SUBST
    READ TABLE lt_zapo_ptc_subst INTO lw_zapo_ptc_subst
      WITH KEY zexmatnr = <ls_sub1>-zexmatnr.
    
    IF sy-subrc <> 0.
      " Try with zldmatnr
      READ TABLE lt_zapo_ptc_subst INTO lw_zapo_ptc_subst
        WITH KEY zldmatnr = <ls_sub1>-zexmatnr.
    ENDIF.
    
    IF sy-subrc = 0.
      " Update GT_SUB1 with values from ZAPO_PTC_SUBST
      <ls_sub1>-zexmatnr = lw_zapo_ptc_subst-zexmatnr.
      <ls_sub1>-zexdesc = lw_zapo_ptc_subst-zexdesc.
      
      " Debug log for specific product
      IF <ls_sub1>-zexmatnr = 'PY1522809R' AND
         <ls_sub1>-zshptp = '3000026743'.
        MESSAGE i004(zapo_subst) WITH 
          'Found ZEXMATNR:' lw_zapo_ptc_subst-zexmatnr
          'ZEXDESC:' lw_zapo_ptc_subst-zexdesc.
      ENDIF.
    ELSE.
      " Log warning if not found
      IF <ls_sub1>-zexmatnr = 'PY1522809R' AND
         <ls_sub1>-zshptp = '3000026743'.
        MESSAGE w005(zapo_subst) WITH 
          'ZAPO_PTC_SUBST record not found for' 
          <ls_sub1>-zexmatnr <ls_sub1>-zshptp.
      ENDIF.
    ENDIF.
    
  ENDLOOP.
  
ENDMETHOD.
```

---

### 4.4 Correction 4: Add Validation for ZEXMATNR and ZEXDESC Before ZPSHP Update

**Location:** Method `create_loc_and_extend_pcat11` - before calling `ZAPO_ZPSHP_MODIFY`

**Issue:** Add validation to ensure `ZEXMATNR` and `ZEXDESC` are not initial before updating ZPSHP.

```abap
" ============================================================
" NEW: Validate ZEXMATNR and ZEXDESC before update
" ============================================================
IF lv_zexmatnr IS INITIAL.
  " Try to get from ZAPO_PTC_SUBST if still empty
  SELECT SINGLE zexmatnr FROM zapo_ptc_subst
    INTO lv_zexmatnr
    WHERE zldmatnr = <ls_excel>-zexmatnr
       OR zexmatnr = <ls_excel>-zexmatnr.
ENDIF.

IF lv_zexdesc IS INITIAL.
  " Try to get from ZAPO_PTC_SUBST if still empty
  SELECT SINGLE zexdesc FROM zapo_ptc_subst
    INTO lv_zexdesc
    WHERE zldmatnr = <ls_excel>-zexmatnr
       OR zexmatnr = <ls_excel>-zexmatnr.
ENDIF.

" Only proceed with ZPSHP update if we have valid data
IF lv_zexmatnr IS NOT INITIAL AND lv_zexdesc IS NOT INITIAL.
  
  " Call function module to update ZPSHP
  CALL FUNCTION 'ZAPO_ZPSHP_MODIFY'
    EXPORTING
      iv_matnr     = <ls_excel>-zexmatnr
      iv_shptp     = <ls_excel>-zshptp
      iv_locid     = <ls_excel>-locid
      iv_zexmatnr  = lv_zexmatnr
      iv_zexdesc   = lv_zexdesc
    EXCEPTIONS
      error        = 1
      OTHERS       = 2.
  
  IF sy-subrc <> 0.
    MESSAGE e006(zapo_subst) WITH 
      'ZPSHP update failed for' <ls_excel>-zexmatnr <ls_excel>-zshptp.
  ENDIF.
  
ELSE.
  " Log warning if data is missing
  MESSAGE w007(zapo_subst) WITH 
    'ZEXMATNR or ZEXDESC is empty for' 
    <ls_excel>-zexmatnr <ls_excel>-zshptp
    '- Skipping ZPSHP update'.
ENDIF.
```

---

### 4.5 Correction 5: Add Debug Logging for Specific Product

**Location:** Method `create_loc_and_extend_pcat11` - add debug section

**Issue:** Add specific debug logging for Product 'PY1522809R' and Ship to Party '3000026743' to track the update process.

```abap
" ============================================================
" DEBUG: Track specific product and ship-to-party
" ============================================================
CONSTANTS: 
  gc_debug_product TYPE matnr VALUE 'PY1522809R',
  gc_debug_shptp TYPE /sapapo/locno VALUE '3000026743'.

" Check if current record matches debug criteria
IF <ls_excel>-zexmatnr = gc_debug_product AND
   <ls_excel>-zshptp = gc_debug_shptp.
  
  " Log input data
  MESSAGE i008(zapo_subst) WITH 
    'DEBUG: Processing PY1522809R / 3000026743'
    'ZEXMATNR:' lv_zexmatnr
    'ZEXDESC:' lv_zexdesc.
  
  " Log location status
  IF <ls_excel>-locid IS NOT INITIAL.
    MESSAGE i009(zapo_subst) WITH 
      'DEBUG: Location ID found:' <ls_excel>-locid.
  ELSE.
    MESSAGE w010(zapo_subst) WITH 
      'DEBUG: Location ID is empty - ZPSHP update will be skipped'.
  ENDIF.
  
  " After ZPSHP update, verify
  IF <ls_excel>-locid IS NOT INITIAL.
    SELECT SINGLE zexmatnr zexdesc FROM zpshp
      INTO (@DATA(lv_updated_zexmatnr), @DATA(lv_updated_zexdesc))
      WHERE matnr = gc_debug_product
        AND shptp = gc_debug_shptp.
    
    IF sy-subrc = 0.
      MESSAGE i011(zapo_subst) WITH 
        'DEBUG: ZPSHP updated successfully'
        'ZEXMATNR:' lv_updated_zexmatnr
        'ZEXDESC:' lv_updated_zexdesc.
    ELSE.
      MESSAGE e012(zapo_subst) WITH 
        'DEBUG: ZPSHP update verification failed'.
    ENDIF.
  ENDIF.
ENDIF.
```

---

## 5. Verification Steps

### 5.1 Pre-Implementation Checks

1. **Verify Data in ZAPO_PTC_SUBST:**
   ```sql
   SELECT zexmatnr, zexdesc, zldmatnr, zshptp
   FROM zapo_ptc_subst
   WHERE zexmatnr = 'PY1522809R'
      OR zldmatnr = 'PY1522809R';
   ```

2. **Verify Current State of ZPSHP:**
   ```sql
   SELECT * FROM zpshp
   WHERE matnr = 'PY1522809R'
     AND shptp = '3000026743';
   ```

3. **Verify Variant TEST_SUBST Settings:**
   - Check if Product 'PY1522809R' is included in material selection
   - Check if Ship to Party '3000026743' is included in ship-to-party selection
   - Verify Category 1 and Category 10 are selected

### 5.2 Post-Implementation Verification

1. **Run Program with Variant TEST_SUBST:**
   - Execute transaction ZSUBST
   - Load variant TEST_SUBST
   - Execute program

2. **Check ZPSHP Table:**
   ```sql
   SELECT matnr, shptp, locid, zexmatnr, zexdesc, erdat, erzet, ernam
   FROM zpshp
   WHERE matnr = 'PY1522809R'
     AND shptp = '3000026743';
   ```

3. **Verify Fields are Populated:**
   - `ZEXMATNR` should contain value from ZAPO_PTC_SUBST
   - `ZEXDESC` should contain value from ZAPO_PTC_SUBST
   - `LOCID` should be populated
   - Timestamp fields should be updated

---

## 6. Testing Checklist

- [ ] Verify `ZAPO_PTC_SUBST` contains data for Product 'PY1522809R'
- [ ] Verify `ZEXMATNR` and `ZEXDESC` exist in `ZAPO_PTC_SUBST` for the product
- [ ] Verify variant `TEST_SUBST` includes Product 'PY1522809R' and Ship to Party '3000026743'
- [ ] Verify location '3000026743' exists in `/SAPAPO/LOC`
- [ ] Verify product 'PY1522809R' is extended to location
- [ ] Run program and check for error messages
- [ ] Verify ZPSHP table is updated after program execution
- [ ] Verify `ZEXMATNR` field is populated in ZPSHP
- [ ] Verify `ZEXDESC` field is populated in ZPSHP
- [ ] Check debug messages for specific product
- [ ] Verify COMMIT WORK is executed after ZPSHP update

---

## 7. Implementation Priority

| Priority | Correction | Impact | Effort |
|----------|------------|--------|--------|
| **P0 (Critical)** | Correction 2: Update Function Module ZAPO_ZPSHP_MODIFY | High - Direct fix for missing fields | Medium |
| **P0 (Critical)** | Correction 1: Enhance create_loc_and_extend_pcat11 | High - Ensures data is read and passed | Medium |
| **P1 (High)** | Correction 3: Update updating_stageing_tables | Medium - Ensures data is available early | Low |
| **P1 (High)** | Correction 4: Add Validation | Medium - Prevents invalid updates | Low |
| **P2 (Medium)** | Correction 5: Add Debug Logging | Low - Helps troubleshooting | Low |

**Recommended Implementation Order:**
1. Start with Correction 2 (Function Module) - This is the direct fix
2. Then Correction 1 (create_loc_and_extend_pcat11) - Ensures data flow
3. Follow with Correction 3 (updating_stageing_tables) - Ensures data availability
4. Then Correction 4 (Validation) - Prevents errors
5. Finally Correction 5 (Debug Logging) - For troubleshooting

---

## 8. Expected Results

### 8.1 Before Correction

- ZPSHP table record for Product 'PY1522809R' and Ship to Party '3000026743' either:
  - Does not exist, OR
  - Exists but `ZEXMATNR` and `ZEXDESC` fields are empty/initial

### 8.2 After Correction

- ZPSHP table record for Product 'PY1522809R' and Ship to Party '3000026743' will:
  - Be created/updated successfully
  - Have `ZEXMATNR` field populated with value from `ZAPO_PTC_SUBST`
  - Have `ZEXDESC` field populated with value from `ZAPO_PTC_SUBST`
  - Have proper timestamp and user information
  - Be committed to database

---

## 9. Field Mapping Reference

| Source Table (ZAPO_PTC_SUBST) | Target Table (ZPSHP) | Notes |
|-------------------------------|----------------------|-------|
| `ZEXMATNR` | `ZEXMATNR` | External Material Number |
| `ZEXDESC` | `ZEXDESC` | External Description |
| `ZLDMATNR` | `MATNR` | Lead Material Number (used for matching) |
| `ZSHPTP` | `SHPTP` | Ship to Party |
| - | `LOCID` | Location ID (from APO location creation) |

---

## 10. Notes

- **Field Names:** Verify actual field names in:
  - Table `ZPSHP` structure (`ZPAPOSHP`)
  - Table `ZAPO_PTC_SUBST` structure
  - Internal table `GT_SUB1` structure
  
- **Function Module Interface:** Verify the actual interface of `ZAPO_ZPSHP_MODIFY` function module. The parameter names and types may need adjustment based on actual definition.

- **Data Type:** `ZEXDESC` may be of type `STRING`, `CHAR`, or `VARCHAR` depending on table definition. Adjust accordingly.

- **Variant Settings:** Ensure variant `TEST_SUBST` is properly configured with:
  - Material selection including 'PY1522809R'
  - Ship-to-party selection including '3000026743'
  - Category 1 and Category 10 selected

- **Testing:** Test thoroughly in QA environment before production deployment. Monitor for any performance impact due to additional SELECT statements.

---

## 11. SQL Queries for Verification

### 11.1 Check Source Data
```sql
SELECT zexmatnr, zexdesc, zldmatnr, zshptp, zexdesc
FROM zapo_ptc_subst
WHERE (zexmatnr = 'PY1522809R' OR zldmatnr = 'PY1522809R')
  AND (zshptp = '3000026743' OR zexdesc = '3000026743');
```

### 11.2 Check Target Data (Before)
```sql
SELECT matnr, shptp, locid, zexmatnr, zexdesc, erdat, erzet
FROM zpshp
WHERE matnr = 'PY1522809R'
  AND shptp = '3000026743';
```

### 11.3 Check Target Data (After)
```sql
SELECT matnr, shptp, locid, zexmatnr, zexdesc, aedat, aezet, aenam
FROM zpshp
WHERE matnr = 'PY1522809R'
  AND shptp = '3000026743'
  AND zexmatnr IS NOT NULL
  AND zexdesc IS NOT NULL;
```

---

**Document Version:** 1.0  
**Created:** 2026-01-28  
**Author:** Code Analysis  
**Status:** Ready for Implementation  
**Related Documents:**
- `Code_Analysis_ZPSHP_Update_Issue_PY1522809R.md`
- `Code_Correction_USER_ACTIVITY_BAPI_Line7782.md`

