# JWTCFG_ACTIVE Selection Approach

## Objective
Allow administrators to control which JWT configuration profile is used at runtime without requiring application code changes.

This approach separates:
- Profile details (stored in JWTCFG)
- Active selection per business function (stored in JWTCFG_ACTIVE)

## Problem Being Solved
If applications call JWTGEN directly, they usually hard-code:
- all signing/claim parameters, or
- a fixed JWTLABEL

Hard-coding creates maintenance risk during rotation, environment changes, and onboarding of new functions.

## Proposed Model
Use two tables with clear responsibilities.

### 1) JWTCFG (existing)
Stores JWT profile details (for example):
- JWTLABEL
- KSFILE, KSLIB, KSLABEL
- JWALG
- ISSUER, SUBJECT, AUDIENCE
- EXPIRY_SEC

JWTCFG remains the authoritative source for profile content.

### 2) JWTCFG_ACTIVE (new)
Stores which JWTLABEL is active for a specific function.

Suggested columns:
- FUNCTION_ID (for example: PAYROLL_API, BATCH_AR, OAUTH_CLIENT_A)
- JWTLABEL
- ACTIVE
- CHGUSR
- CHGTS

Recommended constraints:
- Primary key on FUNCTION_ID if table stores only the current active row per function.
- Foreign key from JWTLABEL to JWTCFG.JWTLABEL.

## Should ACTIVE Be Unique by Function?
Yes, if ACTIVE is stored with multiple rows per function, uniqueness must be enforced by function scope.

Safer pattern:
- Keep only one row per FUNCTION_ID in JWTCFG_ACTIVE (simplest)
- Update JWTLABEL in that row when switching active profile

Alternative pattern:
- Keep history rows with ACTIVE flag
- Then enforce only one ACTIVE='Y' per FUNCTION_ID through app logic or database rule

Recommendation:
- Start with one-row-per-function design for simplicity and reliability.

## Runtime Resolution Flow
1. Caller passes FUNCTION_ID (and runtime subject/overrides as needed).
2. Wrapper program reads JWTLABEL from JWTCFG_ACTIVE for that FUNCTION_ID.
3. Wrapper reads full profile from JWTCFG by JWTLABEL.
4. Wrapper resolves subject rules/defaults.
5. Wrapper calls JWTGEN.
6. Wrapper returns token + result status.

This removes direct dependency on hard-coded JWTLABEL in application code.

## Example SQL DDL (Starter)
```sql
CREATE TABLE JWTCFG_ACTIVE (
  FUNCTION_ID   VARCHAR(64)  NOT NULL,
  JWTLABEL      VARCHAR(36)  NOT NULL,
  CHGUSR        VARCHAR(128) NOT NULL DEFAULT USER,
  CHGTS         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT JWTCFG_ACTIVE_PK PRIMARY KEY (FUNCTION_ID),
  CONSTRAINT JWTCFG_ACTIVE_FK1 FOREIGN KEY (JWTLABEL)
    REFERENCES JWTCFG (JWTLABEL)
);

CREATE INDEX JWTCFGA_I1 ON JWTCFG_ACTIVE (JWTLABEL);
```

Notes:
- If `JWTCFG.JWTLABEL` is not currently unique, add a unique key/index there before adding the foreign key.
- Column types can be adjusted to local naming standards.

## Example Lookup Query
```sql
SELECT c.KSFILE,
       c.KSLIB,
       c.KSLABEL,
       c.JWALG,
       c.ISSUER,
       c.SUBJECT,
       c.AUDIENCE,
       c.EXPIRY_SEC
  FROM JWTCFG_ACTIVE a
  JOIN JWTCFG c
    ON c.JWTLABEL = a.JWTLABEL
 WHERE a.FUNCTION_ID = :inFunctionId;
```

## Admin Workflow
1. Maintain JWT profiles in JWTCFGM.
2. Assign or switch active profile per function in JWTCFG_ACTIVE maintenance.
3. No app code deployment needed to change active profile.
4. Runtime callers continue sending only FUNCTION_ID (and business claims inputs).

## Governance and Operations
Recommended controls:
- Validate FUNCTION_ID exists before issuance.
- Log resolved FUNCTION_ID and JWTLABEL for each token request.
- Restrict who can update JWTCFG_ACTIVE.
- Add a quick test utility to verify active mappings.

## Phased Implementation
Phase 1:
1. Add JWTCFG_ACTIVE table.
2. Add wrapper lookup path using FUNCTION_ID.
3. Keep existing JWTGEN direct path for diagnostics.

Phase 2:
1. Add maintenance UI/program for JWTCFG_ACTIVE.
2. Add audit logging for active profile changes and issuance.

Phase 3:
1. Add optional effective dating and controlled cutover features.

## Recommendation
Adopt JWTCFG_ACTIVE as the runtime selector table and use a wrapper API as the application entry point.

This gives administrators control of active JWT profile selection per function while minimizing hard-coded values in application programs.

## Implementation Artifacts
- src/JWTCFGA.SQL
- src/GETJWACT.RPGLE
- src/TESTJWACT.RPGLE

## Related Documentation
- docs/jwt-issuance-wrapper-proposal.md
- docs/key-label-prefix-proposal.md
- docs/key-types-roadmap.md
- docs/manual-vs-maintenance-flow.md
- docs/program-call-map.md

---
Prepared for review: April 12, 2026
