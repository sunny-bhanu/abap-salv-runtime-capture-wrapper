*&---------------------------------------------------------------------*
*& Report ZR_SALV_RUNTIME_WRAPPER
*&---------------------------------------------------------------------*
*& Clean-core pattern: add columns to a STANDARD report's ALV output
*& without modifying, enhancing or copying the standard program.
*&
*& 1. SUBMIT the standard program (here RM08MMAT = transaction MR51)
*&    with the user's selection screen, AND RETURN.
*& 2. Capture the ALV it produces through CL_SALV_BS_RUNTIME_INFO.
*& 3. Enrich the captured rows with the extra columns we need
*&    (here: material document number + fiscal year from BKPF-AWKEY).
*& 4. Redisplay with CL_SALV_TABLE.
*&
*& Standard authorisation, selection logic and any future SAP
*& corrections to the wrapped program are inherited automatically.
*&---------------------------------------------------------------------*
REPORT zr_salv_runtime_wrapper.

CONSTANTS: gc_std_report TYPE sy-repid VALUE 'RM08MMAT'.

*----------------------------------------------------------------------*
* Enriched output line: standard columns + our additions
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_output,
         bukrs      TYPE bukrs,
         belnr      TYPE belnr_d,
         gjahr      TYPE gjahr,
         buzei      TYPE buzei,
         matnr      TYPE matnr,
         werks      TYPE werks_d,
         dmbtr      TYPE dmbtr,
         waers      TYPE waers,
         awkey      TYPE awkey,
         mat_doc    TYPE mblnr,      " <- added
         mat_year   TYPE mjahr,      " <- added
       END OF ty_output.

CLASS lcl_wrapper DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.
  PRIVATE SECTION.
    DATA mt_output TYPE STANDARD TABLE OF ty_output WITH EMPTY KEY.
    METHODS capture_standard_alv
      RETURNING VALUE(rr_data) TYPE REF TO data
      RAISING   cx_salv_bs_sc_runtime_info.
    METHODS enrich
      IMPORTING ir_data TYPE REF TO data.
    METHODS display
      RAISING cx_salv_error.
ENDCLASS.

CLASS lcl_wrapper IMPLEMENTATION.

  METHOD run.
    TRY.
        DATA(lr_data) = capture_standard_alv( ).
        enrich( lr_data ).
        display( ).
      CATCH cx_salv_bs_sc_runtime_info INTO DATA(lx_rt).
        MESSAGE lx_rt->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
      CATCH cx_salv_error INTO DATA(lx_salv).
        MESSAGE lx_salv->get_text( ) TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD capture_standard_alv.
    " Tell the SALV runtime to intercept the next ALV display
    cl_salv_bs_runtime_info=>set(
      EXPORTING display  = abap_false
                metadata = abap_false
                data     = abap_true ).

    " Hand the user's own selection screen to the standard program.
    " WITH SELECTION-TABLE could be used instead if the parameters are
    " collected in an RSPARAMS table.
    SUBMIT (gc_std_report)
      VIA SELECTION-SCREEN
      AND RETURN.

    " Retrieve the data table the standard program built
    cl_salv_bs_runtime_info=>get_data_ref(
      IMPORTING r_data = rr_data ).

    cl_salv_bs_runtime_info=>clear_all( ).
  ENDMETHOD.

  METHOD enrich.
    FIELD-SYMBOLS <lt_std> TYPE STANDARD TABLE.
    ASSIGN ir_data->* TO <lt_std>.
    IF sy-subrc <> 0 OR <lt_std> IS INITIAL.
      RETURN.
    ENDIF.

    " 1) Move the standard columns we need (MOVE-CORRESPONDING by name)
    LOOP AT <lt_std> ASSIGNING FIELD-SYMBOL(<ls_std>).
      APPEND INITIAL LINE TO mt_output ASSIGNING FIELD-SYMBOL(<ls_out>).
      MOVE-CORRESPONDING <ls_std> TO <ls_out>.
    ENDLOOP.

    " 2) Read the reference key once for all accounting documents
    "    (BKPF-AWKEY = MBLNR(10) + MJAHR(4) for material documents)
    DATA(lt_keys) = mt_output.
    SORT lt_keys BY bukrs belnr gjahr.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING bukrs belnr gjahr.

    IF lt_keys IS NOT INITIAL.
      " Released CDS view I_JournalEntry instead of direct SELECT on BKPF
      SELECT companycode           AS bukrs,
             accountingdocument    AS belnr,
             fiscalyear            AS gjahr,
             referencedocument     AS awkey,
             referencedocumenttype AS awtyp
        FROM i_journalentry
        FOR ALL ENTRIES IN @lt_keys
        WHERE companycode        = @lt_keys-bukrs
          AND accountingdocument = @lt_keys-belnr
          AND fiscalyear         = @lt_keys-gjahr
        INTO TABLE @DATA(lt_bkpf).

      SORT lt_bkpf BY bukrs belnr gjahr.

      LOOP AT mt_output ASSIGNING <ls_out>.
        READ TABLE lt_bkpf ASSIGNING FIELD-SYMBOL(<ls_bkpf>)
             WITH KEY bukrs = <ls_out>-bukrs
                      belnr = <ls_out>-belnr
                      gjahr = <ls_out>-gjahr
             BINARY SEARCH.
        IF sy-subrc = 0 AND <ls_bkpf>-awtyp = 'MKPF'.
          <ls_out>-awkey    = <ls_bkpf>-awkey.
          <ls_out>-mat_doc  = <ls_bkpf>-awkey(10).
          <ls_out>-mat_year = <ls_bkpf>-awkey+10(4).
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD display.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = DATA(lo_alv)
      CHANGING  t_table      = mt_output ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).

    DATA(lo_cols) = lo_alv->get_columns( ).
    DATA(lo_col)  = lo_cols->get_column( 'MAT_DOC' ).
    lo_col->set_short_text( 'Mat.Doc.' ).
    lo_col->set_medium_text( 'Material Doc.' ).
    lo_col->set_long_text( 'Material Document' ).

    lo_col = lo_cols->get_column( 'MAT_YEAR' ).
    lo_col->set_short_text( 'MatYear' ).
    lo_col->set_medium_text( 'Mat.Doc. Year' ).
    lo_col->set_long_text( 'Material Document Year' ).

    lo_alv->display( ).
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  NEW lcl_wrapper( )->run( ).
