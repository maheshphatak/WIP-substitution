# ZAPO_MATERIAL_BALANCE_CLS - TEST Variant Zero Quantity Fix

## Why `TEST-MATBAL` shows zero

In include `ZAPO_MATERIAL_BALANCE_CLS`, mock mode is currently enabled by:

- `IF p_orun CS 'TEST'.` in `generate_material_balance`
- same pattern in `calulate_mat_bal_demand`, `create_dyn_tab`, and `validate_screen`

For `TEST-MATBAL`, this condition is true and method `upd_mock_data_gen_matbal` is called.  
Inside that method, CSV upload logic is commented, so no mock payload is loaded. As a result, totals like `TOT_DMD`, `TOT_SUPPLY`, `OPNG_STK`, `CLSG_STK`, `PROD_QTY` remain initial/zero.

`Test_FG_Matbal` typically does not hit the same branch (case/contents differ), so it runs normal log fetch and returns non-zero quantities.

## Design Change

Use TEST/mock branch only when explicitly in dev mode:

`c_dev = abap_true AND p_orun CP 'TEST*'`

This avoids accidental production/test-variant collisions.

---

## Ready-to-apply ABAP code changes

Use full replacement for the first, second and fourth methods below.  
For `create_dyn_tab`, apply only the shown delta edits (not a full replacement).

```abap
  METHOD generate_material_balance.

    DATA(lv_is_mock_mode) = xsdbool( c_dev = abap_true AND p_orun CP 'TEST*' ).

*    fetch param table data
    me->fetch_param_data( ).

    IF lv_is_mock_mode = abap_true.
*      load mock data from CSV file in given location (dev only)
      me->upd_mock_data_gen_matbal( ).
    ELSE.
*      fetch all log required data
      me->fetch_log_data( ).
    ENDIF.

*    process the bucket of log & change find its starting & ending date
    me->process_buckets( ).
*    calculate the intermediate quantites for producing material
*    balance report
    me->calulate_mat_bal_demand( ).

*    create dynamic table
    me->create_dyn_tab( ).

*    populate the supply qty for the customer based on region for its
*    corresponding source & supply location
    me->populate_supply( ).

    me->get_subtol_for_dmd( ).

    me->populate_demand_qty( ).

    me->populate_other_qty( ).

    me->get_non_prime_stock( ).

    me->save_to_table( ).

  ENDMETHOD.                    "generate_material_balance
```

```abap
  METHOD calulate_mat_bal_demand.

    DATA(lv_is_mock_mode) = xsdbool( c_dev = abap_true AND p_orun CP 'TEST*' ).

    me->calculate_inp_dmd( ).
    IF lv_is_mock_mode = abap_false.
      me->fetch_pb_data( ).
    ENDIF.
    me->calc_spld_dmn_cust_wise( ).
    me->calc_spld_dmn_cust_loc_wise( ).
    me->calculate_prod_qty( ).
    me->demand_location_details( ).
    me->find_stk_txfr_tlanes( ).
    me->find_mat_prod_plant( ).

  ENDMETHOD.                    "calulate_mat_bal_demand
```

### Delta edits for `create_dyn_tab`

1) Add local flag in `DATA` declaration:

```abap
      lv_is_mock_mode     TYPE abap_bool.
```

2) Set it once near the top of method:

```abap
    lv_is_mock_mode = xsdbool( c_dev = abap_true AND p_orun CP 'TEST*' ).
```

3) Replace:

```abap
    IF lt_reg_off IS NOT INITIAL AND NOT p_orun CS 'TEST'.
```

with:

```abap
    IF lt_reg_off IS NOT INITIAL AND lv_is_mock_mode = abap_false.
```

4) Replace:

```abap
    IF p_orun CS 'TEST' AND s_regoff[] IS NOT INITIAL.
```

with:

```abap
    IF lv_is_mock_mode = abap_true AND s_regoff[] IS NOT INITIAL.
```

```abap
  METHOD validate_screen.

    DATA:
      lv_sessionname TYPE /sapapo/sessionname,
      lv_is_mock_mode TYPE abap_bool.

    IF NOT ( sy-ucomm = 'ONLI' OR sy-ucomm = space ).
      RETURN.
    ENDIF.

    lv_is_mock_mode = xsdbool( c_dev = abap_true AND p_orun CP 'TEST*' ).

    IF p_orun IS INITIAL.
      MESSAGE 'Please enter Optimizer Run Name'(018) TYPE 'E'.
    ELSE.
      IF lv_is_mock_mode = abap_true.
        gs_snpop_log_info-sessionname = p_orun.
      ELSE.
        CLEAR lv_sessionname.
        SELECT SINGLE sessionname
          FROM /sapapo/snpopkey
          INTO lv_sessionname
          WHERE sessionname = p_orun.
        IF sy-subrc <> 0.
          MESSAGE 'Invalid Session Name'(052) TYPE 'E'.
        ENDIF.
      ENDIF.
    ENDIF.

  ENDMETHOD.                    "validate_screen
```

---

## Optional hardening (recommended)

1. In `upd_mock_data_gen_matbal`, re-enable CSV upload only when `c_dev = abap_true` and `p_file` provided.
2. Add a warning message when mock mode is active:  
   `"Mock mode active - log tables are not fetched"`.
3. Keep previously identified zero-propagation fixes in:
   - `populate_demand_qty` (fallback to raw `D_<REG>` when SNZ ratio not applied)
   - `populate_other_qty` (do not multiply production/stock by zero numerators)

---

## Quick validation after transport

1. Run variant `TEST-MATBAL` in non-dev context (`c_dev = space`): it should now fetch real log data.
2. Compare with `Test_FG_Matbal`: `Total Demand`, `Total Supply`, `Opening Stock`, `Closing Stock`, `Production` should no longer be globally zero due to mock branch.
3. Confirm no regression for true dev mock runs (`c_dev = X`, `p_orun = TEST*`).

