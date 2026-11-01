# abap-salv-runtime-capture-wrapper

**Add columns to a standard SAP report's ALV output with zero modification, zero enhancement and zero Z-copy.**

Reference implementation of the clean-core "runtime capture wrapper" pattern, generalised from a real S/4HANA (RISE private cloud) requirement: show *Material Document Number* and *Fiscal Year* next to the accounting lines in transaction **MR51** (program `RM08MMAT`).

## The problem

The business wanted two extra columns on MR51. Three designs were evaluated:

| Option | How | Clean-core verdict |
|---|---|---|
| **Implicit enhancement** in `RM08MMAT` | Enhancement point at the end of the output-building form | Built first - then **flagged by the clean-core scorecard** as an enhancement of a standard object. Deactivated and reverted. |
| **Full Z-copy** of `RM08MMAT` | Copy program, add fields | Rejected - forks ~2,000 lines of standard code; no future SAP corrections, selection or authorisation fixes would ever reach the copy. |
| **Runtime-capture wrapper** ✅ | `SUBMIT … AND RETURN` the unmodified standard program, capture its ALV via `CL_SALV_BS_RUNTIME_INFO`, enrich, redisplay | **Chosen.** Zero footprint on standard objects; inherits every future SAP change to MR51's own selection and authorisation logic. |

## How it works

```
Z wrapper report
   │  1. cl_salv_bs_runtime_info=>set( display = abap_false, data = abap_true )
   │  2. SUBMIT rm08mmat VIA SELECTION-SCREEN AND RETURN
   │        └─ standard program runs normally, builds its ALV, but the
   │           SALV runtime swallows the display and keeps the data
   │  3. cl_salv_bs_runtime_info=>get_data_ref( )  → REF TO data
   │  4. MOVE-CORRESPONDING into an enriched structure
   │  5. Read BKPF-AWKEY through released view I_JournalEntry
   │     (AWKEY = MBLNR(10) + MJAHR(4) when AWTYP = 'MKPF')
   └─ 6. cl_salv_table=>factory( … )->display( )
```

See [`zr_salv_runtime_wrapper.prog.abap`](zr_salv_runtime_wrapper.prog.abap).

## Design notes

- **`VIA SELECTION-SCREEN`** reuses the standard program's own selection screen, so the user experience is identical to MR51 and no selection logic is duplicated. If you need to pre-fill or hide parameters, collect them into an `RSPARAMS` table and use `WITH SELECTION-TABLE` instead.
- **Capture only works for SALV / `CL_GUI_ALV_GRID`-based output.** `CL_SALV_BS_RUNTIME_INFO` hooks into the SALV runtime; classic `WRITE` lists need `LIST_FROM_MEMORY` instead.
- **Always `clear_all( )`** after retrieving the data - otherwise the next ALV display in the same session is suppressed too.
- **Read through released CDS views** (`I_JournalEntry`) rather than `SELECT … FROM bkpf` to stay compatible with ABAP Cloud / tier-2 extensibility checks.
- `FOR ALL ENTRIES` is guarded by an `IS NOT INITIAL` check and the driver table is de-duplicated first - see [abap-performance-patterns](https://github.com/sunny-bhanu/abap-performance-patterns).

## When *not* to use this

- When SAP already offers a **released BAdI** for the output table (e.g. `ME_CHANGE_OUTTAB_CUS` for ME2N) - use the BAdI; see [abap-badi-me2n-longtext-column](https://github.com/sunny-bhanu/abap-badi-me2n-longtext-column).
- When the standard program's output is a Fiori Elements app rather than a GUI ALV - extend the underlying CDS view instead.

## Transport / activation

Single executable program; create a transaction code (e.g. `ZMR51`) pointing to it and copy the authorisation object checks from the standard transaction into the new transaction's `S_TCODE` role assignment.

---

*Written as generic reference material. No client data or client-specific logic.*
MIT License - see [LICENSE](LICENSE).
