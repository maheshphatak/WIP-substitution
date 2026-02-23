# WIP2 Material Checkbox Implementation for ZAPO_SNP_DP_DIFF
## Requirement: Add WIP2 Material Selection Option with ZAPOPARAM Table Integration

---

## 1. Overview

**Program:** `ZAPO_SNP_DP_DIFF`  
**Includes:**
- `zapo_snp_dp_diff_top` - Global data declarations
- `ZAPO_SNP_DP_DIFF_SCR` - Selection screen definition
- `ZAPO_SNP_DP_DIFF_CLS` - Class implementation

**Requirement:** Add a checkbox "WIP2 Material" in the Selection Screen for "Update Staging Table Criteria". When checked, the program should:
- Read characteristic `P_SKU_PFY_ZMATNR1` from `ZAPOPARAM` table (`Value4` field)
- Use this characteristic from Planning Book (e.g., PFY_ADM_MTH) instead of `P_SKU_PFY`
- Display `ZMATNR1` Materials (APO Product WIP2) in the DP Quantity output table instead of `9AMATNR` Materials (Material SKU PFY)

When checkbox is not selected:
- Read characteristic `P_SKU_PFY` from `ZAPOPARAM` table (`Value3` field)
- Execute normally with `9AMATNR` materials

---

## 2. Changes Required

### 2.1 Include: `zapo_snp_dp_diff_top`

**Location:** Global data declarations section

**Change:** Add checkbox variable declaration and ZAPOPARAM table structure

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
" NEW: ZAPOPARAM Table Structure
" ============================================================
TYPES: BEGIN OF ty_zapoparam,
         param_name TYPE string,  " Parameter name
         value1     TYPE string,   " Value1 field
         value2     TYPE string,   " Value2 field
         value3     TYPE string,   " Value3 field - stores P_SKU_PFY
         value4     TYPE string,   " Value4 field - stores P_SKU_PFY_ZMATNR1
       END OF ty_zapoparam.

DATA: lt_zapoparam TYPE STANDARD TABLE OF ty_zapoparam,
      lw_zapoparam TYPE ty_zapoparam.

" ============================================================
" Characteristic Names (to be read from ZAPOPARAM)
" ============================================================
DATA: 
  gv_char_sku_pfy      TYPE string,      " Characteristic from Value3
  gv_char_zmatnr1      TYPE string,      " Characteristic from Value4
  gv_char_to_use       TYPE string.      " Characteristic to use based on checkbox

" ============================================================
" Constants for ZAPOPARAM Parameter Name
" ============================================================
CONSTANTS: 
  gc_param_char_sku_pfy TYPE string VALUE 'CHAR_SKU_PFY',      " Parameter name for P_SKU_PFY
  gc_param_char_zmatnr1 TYPE string VALUE 'CHAR_SKU_PFY_ZMATNR1'. " Parameter name for P_SKU_PFY_ZMATNR1
```

---

### 2.2 Include: `ZAPO_SNP_DP_DIFF_SCR`

**Location:** Selection screen definition (in "Update Staging Table Criteria" section)

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
" Selection Screen Initialization
" ============================================================
INITIALIZATION.
  " Set default value for checkbox
  p_wip2_mat = abap_false.

" ============================================================
" Selection Screen Validation
" ============================================================
AT SELECTION-SCREEN.
  " ... existing validation code ...
  
  " Optional: Add validation for WIP2 Material checkbox
  " (if specific conditions need to be met)

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
```

---

### 2.3 Include: `ZAPO_SNP_DP_DIFF_CLS`

**Location:** Class method that updates staging table with planning book characteristics

**Change:** Modify the logic to:
1. Read characteristic names from ZAPOPARAM table (Value3/Value4)
2. Use the appropriate characteristic based on checkbox selection
3. Ensure output table displays correct materials (ZMATNR1 or 9AMATNR)

#### Method 1: Read ZAPOPARAM and Determine Characteristic

```abap
*&---------------------------------------------------------------------*
*& Include          ZAPO_SNP_DP_DIFF_CLS
*&---------------------------------------------------------------------*

" ============================================================
" Method: Read Characteristic from ZAPOPARAM Table
" ============================================================
METHOD get_characteristic_from_param.
  
  DATA: 
    lv_param_name TYPE string,
    lv_char_name  TYPE string.
  
  " ============================================================
  " NEW: Read characteristic from ZAPOPARAM based on checkbox
  " ============================================================
  IF p_wip2_mat = abap_true.
    " Read P_SKU_PFY_ZMATNR1 from Value4
    lv_param_name = gc_param_char_zmatnr1.  " 'CHAR_SKU_PFY_ZMATNR1'
    
    SELECT SINGLE value4 FROM zapoparam
      INTO lv_char_name
      WHERE param_name = lv_param_name.
    
    IF sy-subrc = 0 AND lv_char_name IS NOT INITIAL.
      gv_char_to_use = lv_char_name.  " Should be 'P_SKU_PFY_ZMATNR1'
      gv_char_zmatnr1 = lv_char_name.
    ELSE.
      " Fallback to default if not found in ZAPOPARAM
      MESSAGE w001(zapo_snp_dp) WITH 
        'Characteristic not found in ZAPOPARAM for' lv_param_name
        'Using default P_SKU_PFY_ZMATNR1'.
      gv_char_to_use = 'P_SKU_PFY_ZMATNR1'.
    ENDIF.
    
  ELSE.
    " Read P_SKU_PFY from Value3
    lv_param_name = gc_param_char_sku_pfy.  " 'CHAR_SKU_PFY'
    
    SELECT SINGLE value3 FROM zapoparam
      INTO lv_char_name
      WHERE param_name = lv_param_name.
    
    IF sy-subrc = 0 AND lv_char_name IS NOT INITIAL.
      gv_char_to_use = lv_char_name.  " Should be 'P_SKU_PFY'
      gv_char_sku_pfy = lv_char_name.
    ELSE.
      " Fallback to default if not found in ZAPOPARAM
      MESSAGE w001(zapo_snp_dp) WITH 
        'Characteristic not found in ZAPOPARAM for' lv_param_name
        'Using default P_SKU_PFY'.
      gv_char_to_use = 'P_SKU_PFY'.
    ENDIF.
  ENDIF.
  
  " Log the characteristic being used
  MESSAGE i002(zapo_snp_dp) WITH 
    'Using characteristic:' gv_char_to_use
    'for WIP2 Material:' p_wip2_mat.
  
ENDMETHOD.

" ============================================================
" Method: Update Staging Table with Planning Book Data
" ============================================================
METHOD update_staging_table.
  
  DATA: 
    lv_char_name TYPE string,
    lv_planning_book TYPE string VALUE 'PFY_ADM_MTH',  " Example planning book
    lt_planning_data TYPE TABLE OF ...,  " Adjust based on actual structure
    lw_planning_data TYPE ...,           " Adjust based on actual structure
    lt_staging_data TYPE TABLE OF ...,  " Staging table structure
    lw_staging_data TYPE ...            " Staging table work area
  
  FIELD-SYMBOLS: 
    <lv_char_value> TYPE any,
    <lv_matnr_field> TYPE any.
  
  " ============================================================
  " Step 1: Read characteristic from ZAPOPARAM table
  " ============================================================
  me->get_characteristic_from_param( ).
  lv_char_name = gv_char_to_use.
  
  " ============================================================
  " Step 2: Read planning book data using the characteristic
  " ============================================================
  " Adjust the following based on actual API/function module used
  " Example: Reading planning book characteristics
  
  " Option A: Using BAPI or Function Module
  " CALL FUNCTION 'BAPI_PLANNING_BOOK_GET_CHAR_VALUES'
  "   EXPORTING
  "     planning_book = lv_planning_book
  "     characteristic = lv_char_name
  "   TABLES
  "     char_values = lt_planning_data.
  
  " Option B: Reading from InfoCube/DSO table
  " SELECT * FROM /bic/azxxx_xxx_xxx  " Adjust table name
  "   INTO TABLE lt_planning_data
  "   WHERE planning_book = lv_planning_book
  "     AND characteristic = lv_char_name.
  
  " ============================================================
  " Step 3: Process data and update staging table
  " ============================================================
  LOOP AT lt_planning_data INTO lw_planning_data.
    
    CLEAR lw_staging_data.
    
    " ============================================================
    " NEW: Map characteristic value to material field
    " ============================================================
    IF p_wip2_mat = abap_true.
      " Use ZMATNR1 field for WIP2 materials (APO Product)
      " Map characteristic value to ZMATNR1 field in staging table
      ASSIGN COMPONENT 'ZMATNR1' OF STRUCTURE lw_planning_data 
        TO <lv_char_value>.
      
      IF <lv_char_value> IS ASSIGNED AND <lv_char_value> IS NOT INITIAL.
        " Map to staging table material field
        ASSIGN COMPONENT 'MATNR' OF STRUCTURE lw_staging_data 
          TO <lv_matnr_field>.
        IF <lv_matnr_field> IS ASSIGNED.
          <lv_matnr_field> = <lv_char_value>.  " ZMATNR1 material
        ENDIF.
      ENDIF.
      
    ELSE.
      " Use 9AMATNR field for SKU materials (Material PFY)
      " Map characteristic value to 9AMATNR field in staging table
      ASSIGN COMPONENT '9AMATNR' OF STRUCTURE lw_planning_data 
        TO <lv_char_value>.
      
      IF <lv_char_value> IS ASSIGNED AND <lv_char_value> IS NOT INITIAL.
        " Map to staging table material field
        ASSIGN COMPONENT 'MATNR' OF STRUCTURE lw_staging_data 
          TO <lv_matnr_field>.
        IF <lv_matnr_field> IS ASSIGNED.
          <lv_matnr_field> = <lv_char_value>.  " 9AMATNR material
        ENDIF.
      ENDIF.
    ENDIF.
    
    " Map other fields from planning data to staging table
    " ... existing mapping logic ...
    
    " Append to staging table
    APPEND lw_staging_data TO lt_staging_data.
    
  ENDLOOP.
  
  " ============================================================
  " Step 4: Update staging table
  " ============================================================
  " ... existing logic to update staging table ...
  " MODIFY ... FROM TABLE lt_staging_data.
  
ENDMETHOD.
```

#### Method 2: Complete Implementation with Dynamic Field Assignment

```abap
METHOD update_staging_table.
  
  DATA: 
    lv_char_name TYPE string,
    lv_source_field TYPE string,      " Source field name (ZMATNR1 or 9AMATNR)
    lv_planning_book TYPE string VALUE 'PFY_ADM_MTH',
    lt_planning_data TYPE TABLE OF ...,
    lt_staging_data TYPE TABLE OF ...,
    lw_staging_data TYPE ...
  
  FIELD-SYMBOLS: 
    <ls_planning> TYPE any,
    <lv_char_value> TYPE any,
    <lv_matnr> TYPE any.
  
  " ============================================================
  " Step 1: Read characteristic from ZAPOPARAM
  " ============================================================
  me->get_characteristic_from_param( ).
  lv_char_name = gv_char_to_use.
  
  " ============================================================
  " Step 2: Determine source field based on checkbox
  " ============================================================
  IF p_wip2_mat = abap_true.
    lv_source_field = 'ZMATNR1'.  " APO Product (WIP2)
  ELSE.
    lv_source_field = '9AMATNR'.  " Material (SKU) PFY
  ENDIF.
  
  " ============================================================
  " Step 3: Read planning book data
  " ============================================================
  " Adjust SELECT statement based on actual table structure
  SELECT * FROM /bic/azxxx_xxx_xxx  " Adjust table name
    INTO TABLE lt_planning_data
    WHERE planning_book = lv_planning_book.
  
  " ============================================================
  " Step 4: Process and map to staging table
  " ============================================================
  LOOP AT lt_planning_data ASSIGNING <ls_planning>.
    
    CLEAR lw_staging_data.
    
    " Assign characteristic value dynamically
    ASSIGN COMPONENT lv_source_field OF STRUCTURE <ls_planning> 
      TO <lv_char_value>.
    
    IF <lv_char_value> IS ASSIGNED AND <lv_char_value> IS NOT INITIAL.
      
      " Map to staging table material field
      ASSIGN COMPONENT 'MATNR' OF STRUCTURE lw_staging_data 
        TO <lv_matnr>.
      
      IF <lv_matnr> IS ASSIGNED.
        <lv_matnr> = <lv_char_value>.
      ENDIF.
      
      " Map other fields
      " ... existing mapping logic ...
      
      APPEND lw_staging_data TO lt_staging_data.
      
    ENDIF.
    
  ENDLOOP.
  
  " ============================================================
  " Step 5: Update staging table
  " ============================================================
  " ... existing logic to update staging table ...
  
ENDMETHOD.
```

#### Method 3: Using SELECT with Dynamic WHERE Clause

```abap
METHOD update_staging_table.
  
  DATA: 
    lv_char_name TYPE string,
    lv_source_field TYPE string,
    lv_where_clause TYPE string,
    lv_planning_book TYPE string VALUE 'PFY_ADM_MTH',
    lt_staging_data TYPE TABLE OF ...,
    lw_staging_data TYPE ...
  
  " ============================================================
  " Step 1: Read characteristic from ZAPOPARAM
  " ============================================================
  me->get_characteristic_from_param( ).
  lv_char_name = gv_char_to_use.
  
  " ============================================================
  " Step 2: Determine source field and build WHERE clause
  " ============================================================
  IF p_wip2_mat = abap_true.
    lv_source_field = 'ZMATNR1'.
  ELSE.
    lv_source_field = '9AMATNR'.
  ENDIF.
  
  " Build dynamic WHERE clause
  CONCATENATE lv_source_field 'IS NOT INITIAL' 
    INTO lv_where_clause SEPARATED BY space.
  
  " ============================================================
  " Step 3: Read data with dynamic WHERE clause
  " ============================================================
  " Option A: Using dynamic SELECT
  DATA: lr_dyn_where TYPE REF TO data.
  
  " Option B: Using conditional SELECT
  IF p_wip2_mat = abap_true.
    SELECT * FROM /bic/azxxx_xxx_xxx  " Adjust table name
      INTO TABLE lt_staging_data
      WHERE zmatnr1 IS NOT INITIAL
        AND planning_book = lv_planning_book
        AND characteristic = lv_char_name.
  ELSE.
    SELECT * FROM /bic/azxxx_xxx_xxx  " Adjust table name
      INTO TABLE lt_staging_data
      WHERE 9amatnr IS NOT INITIAL
        AND planning_book = lv_planning_book
        AND characteristic = lv_char_name.
  ENDIF.
  
  " ============================================================
  " Step 4: Process and update staging table
  " ============================================================
  LOOP AT lt_staging_data INTO lw_staging_data.
    " ... existing logic to update staging table ...
  ENDLOOP.
  
ENDMETHOD.
```

---

## 3. Main Program: `ZAPO_SNP_DP_DIFF`

**Location:** Main program initialization

**Change:** Add initialization to read ZAPOPARAM and set default values

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
" Initialization
" ============================================================
INITIALIZATION.
  " Set default value for checkbox
  p_wip2_mat = abap_false.
  
  " Optional: Pre-read ZAPOPARAM to validate entries exist
  " This can be done here or in START-OF-SELECTION

" ============================================================
" Start of Selection
" ============================================================
START-OF-SELECTION.
  
  " Create class instance
  DATA: go_obj TYPE REF TO lcl_snp_dp_diff.
  CREATE OBJECT go_obj.
  
  " Call method to update staging table
  " The method will:
  " 1. Read characteristic from ZAPOPARAM (Value3 or Value4)
  " 2. Use ZMATNR1 or 9AMATNR based on checkbox
  " 3. Update staging table accordingly
  go_obj->update_staging_table( ).
  
  " ... rest of the program logic ...

" ============================================================
" End of Selection
" ============================================================
END-OF-SELECTION.
  " ... existing code ...
```

---

## 4. ZAPOPARAM Table Configuration

### 4.1 Required Entries in ZAPOPARAM Table

The following entries must be maintained in `ZAPOPARAM` table:

| PARAM_NAME | VALUE1 | VALUE2 | VALUE3 | VALUE4 |
|------------|--------|--------|--------|--------|
| CHAR_SKU_PFY | (optional) | (optional) | P_SKU_PFY | (optional) |
| CHAR_SKU_PFY_ZMATNR1 | (optional) | (optional) | (optional) | P_SKU_PFY_ZMATNR1 |

**Note:** Adjust `PARAM_NAME` values based on your actual ZAPOPARAM table structure and naming convention.

### 4.2 SQL to Verify ZAPOPARAM Entries

```sql
-- Check if required entries exist
SELECT param_name, value3, value4
FROM zapoparam
WHERE param_name IN ('CHAR_SKU_PFY', 'CHAR_SKU_PFY_ZMATNR1')
ORDER BY param_name;
```

### 4.3 SQL to Insert/Update ZAPOPARAM Entries (if needed)

```sql
-- Insert/Update entry for P_SKU_PFY (Value3)
INSERT INTO zapoparam VALUES (
  'CHAR_SKU_PFY',  -- param_name
  '',              -- value1
  '',              -- value2
  'P_SKU_PFY',     -- value3
  ''               -- value4
);

-- Insert/Update entry for P_SKU_PFY_ZMATNR1 (Value4)
INSERT INTO zapoparam VALUES (
  'CHAR_SKU_PFY_ZMATNR1',  -- param_name
  '',                      -- value1
  '',                      -- value2
  '',                      -- value3
  'P_SKU_PFY_ZMATNR1'      -- value4
);
```

---

## 5. Implementation Checklist

### 5.1 Include: `zapo_snp_dp_diff_top`
- [ ] Add `p_wip2_mat` variable declaration
- [ ] Add ZAPOPARAM table structure (ty_zapoparam)
- [ ] Add global variables for characteristic names
- [ ] Add constants for ZAPOPARAM parameter names

### 5.2 Include: `ZAPO_SNP_DP_DIFF_SCR`
- [ ] Add checkbox parameter `p_wip2_mat` in selection screen
- [ ] Add checkbox in "Update Staging Table Criteria" block
- [ ] Maintain text elements (TEXT-001, TEXT-002, TEXT-003) in SE80/SE38
- [ ] Add initialization logic if needed

### 5.3 Include: `ZAPO_SNP_DP_DIFF_CLS`
- [ ] Create method `get_characteristic_from_param` to read from ZAPOPARAM
- [ ] Modify `update_staging_table` method to:
  - [ ] Call `get_characteristic_from_param` method
  - [ ] Use characteristic from ZAPOPARAM (Value3 or Value4)
  - [ ] Map ZMATNR1 field when checkbox is checked
  - [ ] Map 9AMATNR field when checkbox is not checked
  - [ ] Ensure output table displays correct materials

### 5.4 ZAPOPARAM Table Configuration
- [ ] Verify/Insert entry for `CHAR_SKU_PFY` with `P_SKU_PFY` in Value3
- [ ] Verify/Insert entry for `CHAR_SKU_PFY_ZMATNR1` with `P_SKU_PFY_ZMATNR1` in Value4
- [ ] Test ZAPOPARAM table reads successfully

### 5.5 Testing
- [ ] Test with checkbox unchecked:
  - [ ] Verify reads `P_SKU_PFY` from ZAPOPARAM Value3
  - [ ] Verify uses `9AMATNR` materials in output
  - [ ] Verify staging table updated correctly
- [ ] Test with checkbox checked:
  - [ ] Verify reads `P_SKU_PFY_ZMATNR1` from ZAPOPARAM Value4
  - [ ] Verify uses `ZMATNR1` materials in output
  - [ ] Verify staging table updated correctly
- [ ] Verify DP Quantity output table shows correct materials in both scenarios

---

## 6. Key Points

### 6.1 Characteristic Selection Logic
- **When `p_wip2_mat = abap_false` (default):**
  - Reads `P_SKU_PFY` from `ZAPOPARAM-Value3`
  - Uses `9AMATNR` field from planning book
  - Output shows Material (SKU) PFY

- **When `p_wip2_mat = abap_true`:**
  - Reads `P_SKU_PFY_ZMATNR1` from `ZAPOPARAM-Value4`
  - Uses `ZMATNR1` field from planning book
  - Output shows APO Product (WIP2)

### 6.2 ZAPOPARAM Table Usage
- Characteristic names are **not hardcoded** but read from ZAPOPARAM table
- `Value3` stores the characteristic for normal execution (`P_SKU_PFY`)
- `Value4` stores the characteristic for WIP2 execution (`P_SKU_PFY_ZMATNR1`)
- This allows flexibility to change characteristics without code changes

### 6.3 Planning Book
- The planning book name (e.g., `PFY_ADM_MTH`) should be used as per existing code
- Both characteristics (`P_SKU_PFY` and `P_SKU_PFY_ZMATNR1`) should exist in the planning book
- Both material fields (`9AMATNR` and `ZMATNR1`) should exist in the planning book data

### 6.4 Output Impact
- The DP Quantity output table will display different materials based on the checkbox selection
- Staging table update logic handles both scenarios correctly
- Material field mapping ensures correct data is displayed

---

## 7. Example Selection Screen Layout

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

## 8. Error Handling

### 8.1 ZAPOPARAM Entry Not Found

If the required ZAPOPARAM entry is not found, the code should:
- Log a warning message
- Use a default characteristic name (fallback)
- Continue execution with the default

```abap
IF sy-subrc <> 0.
  MESSAGE w001(zapo_snp_dp) WITH 
    'ZAPOPARAM entry not found for' lv_param_name
    'Using default characteristic'.
  " Use default
  IF p_wip2_mat = abap_true.
    gv_char_to_use = 'P_SKU_PFY_ZMATNR1'.
  ELSE.
    gv_char_to_use = 'P_SKU_PFY'.
  ENDIF.
ENDIF.
```

### 8.2 Characteristic Not Found in Planning Book

If the characteristic doesn't exist in the planning book:
- Log an error message
- Skip processing for that characteristic
- Continue with other data

### 8.3 Material Field Not Found

If the material field (ZMATNR1 or 9AMATNR) is not found:
- Log a warning
- Skip that record
- Continue with next record

---

## 9. Notes

1. **Field Names:** Adjust field names, table names, and structure names based on the actual ABAP code in your system.

2. **ZAPOPARAM Structure:** Verify the actual structure of ZAPOPARAM table. Field names might be different (e.g., `PARAM_NAME`, `VALUE1`, `VALUE2`, `VALUE3`, `VALUE4`).

3. **Parameter Names:** Adjust `PARAM_NAME` values (`CHAR_SKU_PFY`, `CHAR_SKU_PFY_ZMATNR1`) based on your actual ZAPOPARAM table entries.

4. **Function Modules/BAPIs:** Replace example function modules/BAPIs with the actual ones used in your system for reading planning book data.

5. **Table Structures:** Adjust internal table and structure types based on your actual data structures.

6. **Text Elements:** Maintain text elements in transaction SE80 or SE38:
   - TEXT-001: 'Update Staging Table Criteria'
   - TEXT-002: 'WIP2 Material'
   - TEXT-003: 'Use ZMATNR1 instead of P_SKU_PFY'

7. **Testing:** Thoroughly test both scenarios:
   - With checkbox unchecked (existing behavior with 9AMATNR)
   - With checkbox checked (new WIP2 material behavior with ZMATNR1)

8. **Backward Compatibility:** The default value `abap_false` ensures existing behavior is maintained when checkbox is not selected.

---

## 10. Summary

This implementation adds a checkbox "WIP2 Material" to the selection screen that allows users to choose between:
- **P_SKU_PFY** (from ZAPOPARAM Value3) → **9AMATNR** (Material SKU PFY) - Default behavior
- **P_SKU_PFY_ZMATNR1** (from ZAPOPARAM Value4) → **ZMATNR1** (APO Product WIP2) - New option when checkbox is checked

The change ensures:
- Characteristic names are read from ZAPOPARAM table (not hardcoded)
- DP Quantity output table displays the correct materials based on user selection
- Backward compatibility with existing functionality
- Flexibility to change characteristics via ZAPOPARAM table without code changes

---

**End of Document**

