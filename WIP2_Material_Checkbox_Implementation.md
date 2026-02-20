# WIP2 Material Checkbox Implementation for ZAPO_SNP_DP_DIFF
## Requirement: Add WIP2 Material Selection Option

---

## 1. Overview

**Program:** `ZAPO_SNP_DP_DIFF`  
**Includes:**
- `zapo_snp_dp_diff_top` - Global data declarations
- `ZAPO_SNP_DP_DIFF_SCR` - Selection screen definition
- `ZAPO_SNP_DP_DIFF_CLS` - Class implementation

**Requirement:** Add a checkbox "WIP2 Material" in the Selection Screen for "Update Staging Table Criteria". When checked, the program should use characteristic `ZMATNR1` from Planning Book (e.g., PFY_ADM_MTH) instead of `P_SKU_PFY` for updating the staging table. This ensures the DP Quantity output table displays WIP2 materials (APO Product) instead of SKU materials (Material PFY).

---

## 2. Changes Required

### 2.1 Include: `zapo_snp_dp_diff_top`

**Location:** Global data declarations section

**Change:** Add checkbox variable declaration

```abap
" ============================================================
" NEW: WIP2 Material Checkbox Variable
" ============================================================
DATA: p_wip2_mat TYPE abap_bool.  " Checkbox for WIP2 Material selection
```

**Complete Section Example:**

```abap
*&---------------------------------------------------------------------*
*& Include          ZAPO_SNP_DP_DIFF_TOP
*&---------------------------------------------------------------------*

" ============================================================
" Existing Global Data Declarations
" ============================================================
" ... existing code ...

" ============================================================
" NEW: WIP2 Material Checkbox Variable
" ============================================================
DATA: p_wip2_mat TYPE abap_bool.  " Checkbox for WIP2 Material selection

" ============================================================
" Characteristic Names
" ============================================================
CONSTANTS: 
  gc_char_sku_pfy TYPE string VALUE 'P_SKU_PFY',      " Existing characteristic
  gc_char_zmatnr1 TYPE string VALUE 'ZMATNR1'.         " NEW: WIP2 characteristic
```

---

### 2.2 Include: `ZAPO_SNP_DP_DIFF_SCR`

**Location:** Selection screen definition (after "Update Staging Table Criteria" section)

**Change:** Add checkbox in the selection screen

```abap
*&---------------------------------------------------------------------*
*& Include          ZAPO_SNP_DP_DIFF_SCR
*&---------------------------------------------------------------------*

" ============================================================
" Existing Selection Screen Code
" ============================================================
" ... existing selection screen parameters ...

" ============================================================
" Update Staging Table Criteria Section
" ============================================================
SELECTION-SCREEN BEGIN OF BLOCK b_staging WITH FRAME TITLE TEXT-001.
  " ... existing parameters for staging table update ...

  " ============================================================
  " NEW: WIP2 Material Checkbox
  " ============================================================
  SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN COMMENT 1(30) TEXT-002 FOR FIELD p_wip2_mat.
    PARAMETERS: p_wip2_mat AS CHECKBOX DEFAULT abap_false.
    SELECTION-SCREEN COMMENT 35(50) TEXT-003.
  SELECTION-SCREEN END OF LINE.

SELECTION-SCREEN END OF BLOCK b_staging.

" ============================================================
" Text Elements (to be maintained in SE80/SE38)
" ============================================================
" TEXT-001: 'Update Staging Table Criteria'
" TEXT-002: 'WIP2 Material'
" TEXT-003: 'Use ZMATNR1 instead of P_SKU_PFY'
```

**Alternative Implementation (if block structure is different):**

```abap
" ============================================================
" Update Staging Table Criteria
" ============================================================
" ... existing selection screen code ...

" NEW: WIP2 Material Checkbox
PARAMETERS: p_wip2_mat AS CHECKBOX 
            DEFAULT abap_false
            USER-COMMAND ucomm_wip2.

" ============================================================
" Selection Screen Output (if needed for dynamic display)
" ============================================================
AT SELECTION-SCREEN OUTPUT.
  " ... existing code ...
  
  " Optional: Display information message when checkbox is checked
  IF p_wip2_mat = abap_true.
    " You can add visual indicators here if needed
  ENDIF.

" ============================================================
" Selection Screen Validation (if needed)
" ============================================================
AT SELECTION-SCREEN.
  " ... existing validation code ...
  
  " Optional: Add validation for WIP2 Material checkbox
  " (if specific conditions need to be met)
```

---

### 2.3 Include: `ZAPO_SNP_DP_DIFF_CLS`

**Location:** Class method that updates staging table with planning book characteristics

**Change:** Modify the logic to use `ZMATNR1` when checkbox is checked, otherwise use `P_SKU_PFY`

#### Method 1: If characteristic name is determined in a method

```abap
*&---------------------------------------------------------------------*
*& Include          ZAPO_SNP_DP_DIFF_CLS
*&---------------------------------------------------------------------*

" ============================================================
" Method: Update Staging Table with Planning Book Data
" ============================================================
METHOD update_staging_table.
  
  DATA: 
    lv_char_name TYPE string,           " Characteristic name to use
    lt_planning_data TYPE TABLE OF ..., " Adjust based on actual structure
    lw_planning_data TYPE ...            " Adjust based on actual structure
  
  " ============================================================
  " NEW: Determine which characteristic to use based on checkbox
  " ============================================================
  IF p_wip2_mat = abap_true.
    " Use ZMATNR1 for WIP2 Materials (APO Product)
    lv_char_name = gc_char_zmatnr1.  " 'ZMATNR1'
  ELSE.
    " Use P_SKU_PFY for SKU Materials (Material PFY)
    lv_char_name = gc_char_sku_pfy.  " 'P_SKU_PFY'
  ENDIF.
  
  " ============================================================
  " Existing logic to read planning book data
  " Replace hardcoded 'P_SKU_PFY' with lv_char_name
  " ============================================================
  
  " Example: Reading planning book characteristics
  " (Adjust based on actual API/function module used)
  CALL FUNCTION 'SOME_PLANNING_BOOK_FUNCTION'
    EXPORTING
      iv_planning_book = 'PFY_ADM_MTH'      " Example planning book
      iv_characteristic = lv_char_name      " NEW: Use dynamic characteristic
    IMPORTING
      et_data = lt_planning_data.
  
  " Process the data and update staging table
  LOOP AT lt_planning_data INTO lw_planning_data.
    " ... existing logic to update staging table ...
    
    " The output will now contain ZMATNR1 materials if checkbox is checked
    " or P_SKU_PFY materials if checkbox is not checked
  ENDLOOP.
  
ENDMETHOD.
```

#### Method 2: If characteristic is used in SELECT statement

```abap
METHOD update_staging_table.
  
  DATA: 
    lv_char_name TYPE string,
    lt_staging_data TYPE TABLE OF ...,  " Adjust based on actual structure
    lw_staging_data TYPE ...            " Adjust based on actual structure
  
  " ============================================================
  " NEW: Determine which characteristic to use
  " ============================================================
  IF p_wip2_mat = abap_true.
    lv_char_name = gc_char_zmatnr1.  " 'ZMATNR1'
  ELSE.
    lv_char_name = gc_char_sku_pfy.  " 'P_SKU_PFY'
  ENDIF.
  
  " ============================================================
  " Example: Reading from planning book table/view
  " (Adjust table name and field names based on actual structure)
  " ============================================================
  
  " Option A: Using dynamic WHERE clause
  DATA: lv_where_clause TYPE string.
  
  CONCATENATE lv_char_name 'IS NOT INITIAL' INTO lv_where_clause
    SEPARATED BY space.
  
  " Example SELECT (adjust based on actual table structure)
  SELECT * FROM /bic/azxxx_xxx_xxx  " Adjust table name
    INTO TABLE lt_staging_data
    WHERE (lv_where_clause)
      AND planning_book = 'PFY_ADM_MTH'.  " Example planning book
  
  " Option B: Using CASE statement in SELECT
  IF p_wip2_mat = abap_true.
    SELECT * FROM /bic/azxxx_xxx_xxx
      INTO TABLE lt_staging_data
      WHERE zmatnr1 IS NOT INITIAL
        AND planning_book = 'PFY_ADM_MTH'.
  ELSE.
    SELECT * FROM /bic/azxxx_xxx_xxx
      INTO TABLE lt_staging_data
      WHERE p_sku_pfy IS NOT INITIAL
        AND planning_book = 'PFY_ADM_MTH'.
  ENDIF.
  
  " Process and update staging table
  LOOP AT lt_staging_data INTO lw_staging_data.
    " ... existing logic ...
  ENDLOOP.
  
ENDMETHOD.
```

#### Method 3: If using BAPI or Function Module for Planning Book

```abap
METHOD update_staging_table.
  
  DATA: 
    lv_char_name TYPE string,
    lt_char_values TYPE TABLE OF bapi_char_values,
    lw_char_values TYPE bapi_char_values,
    lt_planning_data TYPE TABLE OF ...,
    lv_planning_book TYPE string VALUE 'PFY_ADM_MTH'.
  
  " ============================================================
  " NEW: Determine which characteristic to use
  " ============================================================
  IF p_wip2_mat = abap_true.
    lv_char_name = gc_char_zmatnr1.  " 'ZMATNR1'
  ELSE.
    lv_char_name = gc_char_sku_pfy.  " 'P_SKU_PFY'
  ENDIF.
  
  " ============================================================
  " Read planning book characteristic values
  " (Adjust function module/BAPI based on actual implementation)
  " ============================================================
  
  " Example using BAPI (adjust based on actual BAPI used)
  CALL FUNCTION 'BAPI_PLANNING_BOOK_GET_CHAR_VALUES'
    EXPORTING
      planning_book = lv_planning_book
      characteristic = lv_char_name      " NEW: Dynamic characteristic
    TABLES
      char_values = lt_char_values.
  
  " Process characteristic values and update staging table
  LOOP AT lt_char_values INTO lw_char_values.
    " Map to staging table structure
    " ... existing logic ...
  ENDLOOP.
  
ENDMETHOD.
```

#### Method 4: Complete Example with Field Mapping

```abap
METHOD update_staging_table.
  
  DATA: 
    lv_char_name TYPE string,
    lv_char_field TYPE string,
    lt_source_data TYPE TABLE OF ...,
    lt_staging_data TYPE TABLE OF ...,
    lw_staging_data TYPE ...,
    lv_planning_book TYPE string VALUE 'PFY_ADM_MTH'.
  
  FIELD-SYMBOLS: <lv_char_value> TYPE any.
  
  " ============================================================
  " NEW: Determine which characteristic to use
  " ============================================================
  IF p_wip2_mat = abap_true.
    lv_char_name = gc_char_zmatnr1.  " 'ZMATNR1'
    lv_char_field = 'ZMATNR1'.       " Field name in source table
  ELSE.
    lv_char_name = gc_char_sku_pfy.  " 'P_SKU_PFY'
    lv_char_field = 'P_SKU_PFY'.     " Field name in source table
  ENDIF.
  
  " ============================================================
  " Read data from planning book
  " ============================================================
  " Adjust SELECT statement based on actual table structure
  SELECT * FROM /bic/azxxx_xxx_xxx  " Adjust table name
    INTO TABLE lt_source_data
    WHERE planning_book = lv_planning_book.
  
  " ============================================================
  " Process and map to staging table
  " ============================================================
  LOOP AT lt_source_data ASSIGNING FIELD-SYMBOL(<ls_source>).
    
    CLEAR lw_staging_data.
    
    " Assign characteristic value dynamically
    ASSIGN COMPONENT lv_char_field OF STRUCTURE <ls_source> 
      TO <lv_char_value>.
    
    IF <lv_char_value> IS ASSIGNED AND <lv_char_value> IS NOT INITIAL.
      " Map to staging table
      lw_staging_data-material = <lv_char_value>.  " Adjust field name
      " ... map other fields ...
      
      APPEND lw_staging_data TO lt_staging_data.
    ENDIF.
    
  ENDLOOP.
  
  " ============================================================
  " Update staging table
  " ============================================================
  " ... existing logic to update staging table ...
  
ENDMETHOD.
```

---

## 3. Main Program: `ZAPO_SNP_DP_DIFF`

**Location:** Main program (if any initialization or validation is needed)

**Change:** Add any necessary initialization or validation

```abap
*&---------------------------------------------------------------------*
*& Report  ZAPO_SNP_DP_DIFF
*&---------------------------------------------------------------------*
REPORT zapo_snp_dp_diff.

" ============================================================
" Includes
" ============================================================
INCLUDE zapo_snp_dp_diff_top.    " Global data declarations
INCLUDE zapo_snp_dp_diff_scr.    " Selection screen
INCLUDE zapo_snp_dp_diff_cls.    " Class implementation

" ============================================================
" Initialization (if needed)
" ============================================================
INITIALIZATION.
  " Set default value for checkbox (optional)
  p_wip2_mat = abap_false.

" ============================================================
" Start of Selection
" ============================================================
START-OF-SELECTION.
  
  " Create class instance
  DATA: go_obj TYPE REF TO lcl_snp_dp_diff.
  CREATE OBJECT go_obj.
  
  " Call method to update staging table
  " The method will use ZMATNR1 or P_SKU_PFY based on checkbox
  go_obj->update_staging_table( ).
  
  " ... rest of the program logic ...

" ============================================================
" End of Selection
" ============================================================
END-OF-SELECTION.
  " ... existing code ...
```

---

## 4. Implementation Checklist

### 4.1 Include: `zapo_snp_dp_diff_top`
- [ ] Add `p_wip2_mat` variable declaration
- [ ] Add constants for characteristic names (`gc_char_sku_pfy`, `gc_char_zmatnr1`)

### 4.2 Include: `ZAPO_SNP_DP_DIFF_SCR`
- [ ] Add checkbox parameter `p_wip2_mat` in selection screen
- [ ] Add checkbox in "Update Staging Table Criteria" block
- [ ] Maintain text elements (TEXT-001, TEXT-002, TEXT-003) in SE80/SE38
- [ ] Add any necessary AT SELECTION-SCREEN logic (if validation needed)

### 4.3 Include: `ZAPO_SNP_DP_DIFF_CLS`
- [ ] Identify the method that reads planning book characteristics
- [ ] Replace hardcoded `P_SKU_PFY` with conditional logic
- [ ] Use `ZMATNR1` when `p_wip2_mat = abap_true`
- [ ] Use `P_SKU_PFY` when `p_wip2_mat = abap_false`
- [ ] Ensure output table displays correct materials based on selection

### 4.4 Testing
- [ ] Test with checkbox unchecked (should use P_SKU_PFY)
- [ ] Test with checkbox checked (should use ZMATNR1)
- [ ] Verify DP Quantity output table shows correct materials
- [ ] Verify staging table is updated correctly in both scenarios

---

## 5. Key Points

### 5.1 Characteristic Selection Logic
- **When `p_wip2_mat = abap_false` (default):** Use `P_SKU_PFY` → Output shows Material (SKU) PFY
- **When `p_wip2_mat = abap_true`:** Use `ZMATNR1` → Output shows APO Product (WIP2)

### 5.2 Planning Book
- The planning book name (e.g., `PFY_ADM_MTH`) should be used as per existing code
- Both characteristics (`P_SKU_PFY` and `ZMATNR1`) should exist in the planning book

### 5.3 Output Impact
- The DP Quantity output table will display different materials based on the checkbox selection
- Staging table update logic should handle both scenarios correctly

---

## 6. Example Selection Screen Layout

```
┌─────────────────────────────────────────────────────────┐
│ Update Staging Table Criteria                           │
├─────────────────────────────────────────────────────────┤
│ ... existing parameters ...                             │
│                                                          │
│ ☐ WIP2 Material    Use ZMATNR1 instead of P_SKU_PFY   │
│                                                          │
│ ... other parameters ...                                │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Notes

1. **Field Names:** Adjust field names, table names, and structure names based on the actual ABAP code in your system.

2. **Function Modules/BAPIs:** Replace example function modules/BAPIs with the actual ones used in your system for reading planning book data.

3. **Table Structures:** Adjust internal table and structure types based on your actual data structures.

4. **Text Elements:** Maintain text elements in transaction SE80 or SE38:
   - TEXT-001: 'Update Staging Table Criteria'
   - TEXT-002: 'WIP2 Material'
   - TEXT-003: 'Use ZMATNR1 instead of P_SKU_PFY'

5. **Testing:** Thoroughly test both scenarios:
   - With checkbox unchecked (existing behavior)
   - With checkbox checked (new WIP2 material behavior)

6. **Backward Compatibility:** The default value `abap_false` ensures existing behavior is maintained when checkbox is not selected.

---

## 8. Additional Considerations

### 8.1 Error Handling
Consider adding validation to ensure:
- Planning book exists
- Selected characteristic exists in planning book
- Data is available for the selected characteristic

### 8.2 Performance
- If reading large volumes of data, consider adding selection criteria
- Index the characteristic fields in source tables if possible

### 8.3 Documentation
- Update program documentation to reflect the new checkbox option
- Document the difference between P_SKU_PFY and ZMATNR1 materials

---

## 9. Summary

This implementation adds a checkbox "WIP2 Material" to the selection screen that allows users to choose between:
- **P_SKU_PFY** (Material SKU PFY) - Default behavior
- **ZMATNR1** (APO Product WIP2) - New option when checkbox is checked

The change ensures the DP Quantity output table displays the correct materials based on user selection, while maintaining backward compatibility with existing functionality.

---

**End of Document**

