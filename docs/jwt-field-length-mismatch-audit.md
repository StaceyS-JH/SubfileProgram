# JWT Field Length Mismatch Audit

Date: 2026-04-14
Scope: JWT configuration and signing flow in SubfileProgram

## Purpose
Document field-length mismatches across SQL schema, RPG interfaces, and DSPF screens so we can standardize lengths and avoid truncation/runtime failures.

## Executive Summary
The most important mismatches are:
1. `AUDIENCE` is `VARCHAR(256)` in `JWTCFG`, but `JWTGEN` accepts only `128` chars for audience claims.
2. Maintenance DSPF fields for issuer/subject/audience are `100A`, while backing columns/program variables are larger.
3. `JWALG` is modeled as `CHAR(10)` in config layers but `CHAR(8)` in `JWTGEN` call interface.

## Mismatch Matrix

| Field | DB / Config Definition | Program / UI Definition | Impact | Severity |
|---|---|---|---|---|
| `AUDIENCE` | `JWTCFG.AUDIENCE VARCHAR(256)` | `JWTGEN` audience parm is `128A` | Values over 128 cannot be signed by current `JWTGEN` interface; caller must truncate/reject. | High |
| `ISSUER` | `JWTCFG.ISSUER VARCHAR(128)` | DSPF maintenance field `DISSUER 100A` | UI entry truncates values above 100. | High |
| `SUBJECT` | `JWTCFG.SUBJECT VARCHAR(128)` | DSPF maintenance field `DISUBJECT 100A` | UI entry truncates values above 100. | High |
| `AUDIENCE` (UI) | `JWTCFG.AUDIENCE VARCHAR(256)` | DSPF maintenance field `DIAUDINC 100A` | UI entry truncates values above 100. | High |
| `JWALG` | `JWTCFG.JWALG CHAR(10)` | `JWTGEN` algorithm parm is `8A` | Potential silent truncation if longer algorithm token is ever introduced. | Medium |

## Confirmed Runtime Guard Already Added
`GETACCTKN` currently prevents over-length values from flowing into `JWTGEN` by validating issuer/subject/audience lengths before calling `JWTGEN`.

## Fields Verified as Consistent
These are consistent across the main config path (`JWTCFG`, `GETJWTCFG`, `JWTCFGM`):
- `JWTLABEL` = 36
- `KSFILE` = 10
- `KSLIB` = 10
- `KSLABEL` = 32
- `KEYTYPE` = 11
- `KEYLEN` = integer

## Recommended Standardization Plan
1. Pick canonical claim lengths and enforce in all layers.
   - If long URLs must be supported, increase `JWTGEN` claim parameter handling beyond `128` or redesign input transport.
2. Align maintenance DSPF lengths with canonical DB lengths.
   - At minimum, remove current `100A` bottleneck for issuer/subject/audience.
3. Unify `JWALG` width end-to-end.
   - Either use `8` everywhere (tight JWT token model) or move `JWTGEN` to `10` for consistency with config/UI.
4. Keep explicit length validation at API boundaries.
   - Continue fail-fast errors where a caller passes values larger than downstream contracts.

## Suggested Follow-Up Implementation Order
1. Decide canonical widths (`ISSUER`, `SUBJECT`, `AUDIENCE`, `JWALG`).
2. Update program interfaces first (`JWTGEN`, wrappers).
3. Update DSPF/RPG screen fields.
4. Re-test create/update/read/token-generation paths.

## Notes
- Existing migration comments in `JWTCFG.SQL` still reference `JWALG CHAR(8)`, while current table definition is `CHAR(10)`.
- This is not a production break by itself, but it can cause confusion during future migrations.
