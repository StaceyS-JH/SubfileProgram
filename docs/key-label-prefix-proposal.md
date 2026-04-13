# Key Label Prefix Proposal

## Objective
Introduce a lightweight naming convention for keystore key labels so users can identify key purpose quickly without adding another metadata table.

This proposal keeps your current architecture simple and improves operator clarity during key creation and key selection.

## Problem
Today, users can create any 32-character key label. That is flexible, but it can be hard to tell at a glance whether a key is intended for:
- JWT signing
- encryption
- verification
- other uses

You want usability guidance without building and maintaining another key-function mapping table.

## Proposed Approach
Use a structured key label format created at key-generation time:

`<FUNCTION>-<SUFFIX>`

Where:
- `FUNCTION` is a short purpose code entered by the user (5 or 10 chars)
- `SUFFIX` is the user-entered unique portion

Examples:
- `JWT01-CUSTAPI-2026A`
- `OAUTH-SIGNING-PROD1`
- `ENCRP-BATCH-AR-01`

## Why This Works
- No new database table required
- Key purpose becomes visible directly in the label
- Works with your existing GENKEY/JWTGEN flow
- Supports manual and maintenance flows consistently

## Technical Constraint
The key label accepted by the Qc3 APIs used in this solution is 32 characters.

Relevant implementation evidence in this project:
- GENKEY uses `char(32)` for record label
- JWTGEN KEYD0400 record label is `char(32)`
- LSTKSRCD prompt currently collects a 32-char label field

Therefore, the constructed label must always be `<= 32`.

## Screen/Program Design
Implement in the LSTKSRCD Generate Key prompt:

1. Add `Function` input field (`GKYFUNC`) of either 5 or 10 chars.
2. Reduce free-form suffix input (`GKYLABEL`) so final constructed label fits 32 chars.
3. Build final label in RPG before calling GENKEY:
   - `FinalLabel = %trimr(%upper(GKYFUNC)) + '-' + %trimr(%upper(GKYLABEL))`
4. Validate final length and required fields.
5. Call GENKEY with `FinalLabel`.

## Length Options
### Option A: 5-char function code
- Function field: 5
- Dash: 1
- Suffix max: 26
- Total max: 32

Formula:
`5 + 1 + 26 = 32`

### Option B: 10-char function code
- Function field: 10
- Dash: 1
- Suffix max: 21
- Total max: 32

Formula:
`10 + 1 + 21 = 32`

## Recommendation
Start with 5-char function code.

Why:
- More room for meaningful suffixes
- Easier uniqueness and readability
- Still enough for purpose abbreviations (`JWT`, `OATH`, `ENCRP`, `VRFY1`)

## Validation Rules (Soft Governance)
Use non-blocking governance where possible:

Required:
- Function code must not be blank
- Suffix must not be blank
- Final label length must be `<= 32`

Suggested (not strict hard enforcement unless you want it):
- Uppercase normalization
- Allowed characters: A-Z, 0-9, dash, underscore
- Show user hint text with examples on prompt screen

## Migration/Compatibility
- Existing labels remain valid
- New naming format applies to newly generated keys
- No change required in JWTGEN contract
- No change required in JWTCFG table design

## Operational Benefits
- Faster key selection in prompts and maintenance screens
- Lower chance of selecting the wrong key
- Reduced need for external naming documentation

## Risks and Mitigations
Risk:
- Users may still enter inconsistent function codes.

Mitigation:
- Publish a short approved function code list in documentation.
- Optionally default function code from KSCFG.FUNCTION when available.

Risk:
- Suffix may be too short in some naming conventions.

Mitigation:
- Prefer 5-char function code to preserve suffix space.

## Implementation Steps
1. Update `LSTKSRCD.DSPF` generate prompt to add function code field and adjusted suffix length.
2. Update `LSTKSRCD.RPGLE` GenerateKey procedure to construct and validate final label.
3. Add brief user guidance text to screen and docs.
4. Regression test key generation for RSA and ECC algorithms.

## Success Criteria
- New keys are generated with consistent `<FUNCTION>-<SUFFIX>` labels.
- No generated label exceeds 32 characters.
- Users can identify key purpose from label alone in common workflows.

## Related Documents
- docs/manual-vs-maintenance-flow.md
- docs/jwt-issuance-wrapper-proposal.md
- docs/jwtcfg-active-selection-approach.md
- docs/key-types-roadmap.md
- docs/program-call-map.md

---
Prepared for review: April 12, 2026
