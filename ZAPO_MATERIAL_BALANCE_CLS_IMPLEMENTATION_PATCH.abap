*&---------------------------------------------------------------------*
*&  ZAPO_MATERIAL_BALANCE_CLS — Implementation patch (May 2026)
*&  Apply snippets into include ZAPO_MATERIAL_BALANCE_CLS or use the
*&  full file: ZAPO_MATERIAL_BALANCE_CLS.txt in this folder.
*&  See: ZAPO_MATERIAL_BALANCE_Implementation_CodeChange.md
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------
* 1) upd_mock_data_gen_matbal — CSV only when dev + p_file
*----------------------------------------------------------------------
    IF c_dev = abap_true AND p_file IS NOT INITIAL.
      lv_file_path = p_file && '\csv'.
      ycl_helper_csv_upd_dwn=>upload_csv_to_internal_table(
        EXPORTING
          iv_upload_path       = lv_file_path
          iv_tbl_contains_srno = abap_true
          it_internal_tbl_list = lt_tab_list
          io_class_ref         = me
      ).
    ENDIF.

*----------------------------------------------------------------------
* 2) generate_material_balance
*----------------------------------------------------------------------
  METHOD generate_material_balance.

    DATA(lv_is_mock_mode) = xsdbool( c_dev = abap_true AND p_orun CP 'TEST*' ).

    me->fetch_param_data( ).

    IF lv_is_mock_mode = abap_true.
      me->upd_mock_data_gen_matbal( ).
    ELSE.
      me->fetch_log_data( ).
    ENDIF.

    me->process_buckets( ).
    me->calulate_mat_bal_demand( ).
    me->create_dyn_tab( ).
    me->populate_supply( ).
    me->get_subtol_for_dmd( ).
    me->populate_demand_qty( ).
    me->populate_other_qty( ).
    me->get_non_prime_stock( ).
    me->save_to_table( ).

  ENDMETHOD.

*----------------------------------------------------------------------
* 3) calulate_mat_bal_demand
*----------------------------------------------------------------------
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

  ENDMETHOD.

*----------------------------------------------------------------------
* 4) create_dyn_tab — deltas
*----------------------------------------------------------------------
*   DATA: lv_is_mock_mode TYPE abap_bool.
*   lv_is_mock_mode = xsdbool( c_dev = abap_true AND p_orun CP 'TEST*' ).
*   IF lt_reg_off IS NOT INITIAL AND lv_is_mock_mode = abap_false.  " BW texts
*   IF lv_is_mock_mode = abap_true AND s_regoff[] IS NOT INITIAL.   " filter
*   Display: IF lt_reg_off IS INITIAL AND gt_matbal_hrd IS NOT INITIAL.
*             APPEND 'OTHR' TO lt_reg_off.

*----------------------------------------------------------------------
* 5) validate_screen
*----------------------------------------------------------------------
  METHOD validate_screen.

    DATA:
      lv_sessionname  TYPE /sapapo/sessionname,
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

  ENDMETHOD.

*----------------------------------------------------------------------
* 6) populate_demand_qty — PROD_QTY + pre-aggregation (see full include)
*     - lt_supply_src_sum / lt_supply_out_sum / lt_demand_in_sum
*     - lv_dmd_ratio_used fallback
*     - PROD_QTY: tot_dmd/tot_supply + D_OTHR/S_OTHR assign
*----------------------------------------------------------------------

*----------------------------------------------------------------------
* 7) append_for_db_upd — PROD_QTY OTHR item fallback
*----------------------------------------------------------------------
*   lv_item_written flag in region loop
*   After ENDLOOP:
    IF lv_item_written = abap_false
       AND ls_fin_fields-added_by_method = 'PROD_QTY'
       AND ( ls_fin_qty-tot_dmd IS NOT INITIAL OR ls_fin_qty-tot_supply IS NOT INITIAL ).
      APPEND INITIAL LINE TO gt_matbal_item ASSIGNING <lfs_matbal_item>.
      <lfs_matbal_item>-reg_off = 'OTHR'.
      " demand_qty / supply_qty from ls_fin_qty-tot_dmd / tot_supply (KG /1000)
    ENDIF.
