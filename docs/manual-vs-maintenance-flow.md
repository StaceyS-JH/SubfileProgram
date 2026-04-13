# Manual Flow vs Maintenance Program Flow

## Purpose
This guide compares two ways to run the JWT/keystore solution:
- Manual, parameter-driven program calls
- Guided use of the interactive maintenance programs

It is intended to help operators and developers choose the right path for setup, troubleshooting, and production use.

## Quick Summary
| Area | Manual Flow | Maintenance Program Flow |
|---|---|---|
| Speed for experienced users | Fast once parameters are known | Fast for repeatable operations with prompts |
| Learning curve | Higher (must know each parameter) | Lower (screens guide required inputs) |
| Risk of input mistakes | Higher | Lower (prompt and validation support) |
| Auditable config reuse | Optional unless you store it yourself | Strong (JWTCFG and KSCFG maintenance) |
| Best use case | Testing, automation, diagnostics | Day-to-day operations and admin workflows |

## Programs Involved
### Core callable programs (manual capable)
- CRTKS (create keystore)
- GENKEY (generate key pair)
- JWTGEN (generate JWT)
- GETJWTCFG (lookup JWT parameters by JWTLABEL)

### Interactive maintenance programs
- OAUTHMENU (launcher)
- CRTKSD (guided create keystore)
- LSTKSRCD (list keys and generate keys)
- KSCFGM (keystore config maintenance)
- JWTCFGM (JWT config maintenance)
- PRMKSCFG, PRMKSRCD, ALGPMT (F4 prompt helpers)

## Flow 1: Fully Manual
Use this when you want full control of every parameter.

### 1) Create keystore
Example:

```cl
CALL PGM(MYLIB/CRTKS) PARM('JWTKEYS   ' 'MYLIB     ' 1 'JWT key store for tokens                             ' '*EXCLUDE ')
```

Inputs you provide:
- Keystore file
- Library
- Master key id
- Optional description
- Optional public authority

### 2) Generate key pair
Example (RSA):

```cl
CALL PGM(MYLIB/GENKEY) PARM('JWTKEYS   ' 'MYLIB     ' 'RSA2048   ' 'JWT_RSA_PRIV                    ')
```

Example (ECC):

```cl
CALL PGM(MYLIB/GENKEY) PARM('JWTKEYS   ' 'MYLIB     ' 'ECC_P256  ' 'JWT_ECC_P256_PRIV               ')
```

Inputs you provide:
- Keystore file and library
- Key algorithm selector
- Key label

### 3) Generate JWT by passing all claims manually
Example:

```cl
CALL PGM(MYLIB/JWTGEN) PARM(
  'JWTKEYS   '
  'MYLIB     '
  'JWT_RSA_PRIV                    '
  'RS256   '
  'https://mycompany.example.com                                                                                     '
  'jdoe@example.com                                                                                                  '
  'https://api.example.com                                                                                            '
  3600
  'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
  &JWTOUT
)
```

Inputs you provide:
- Keystore file and library
- Private key label
- JWT algorithm
- Issuer, subject, audience
- Expiration seconds
- JTI (optional if blank)

Notes:
- TESTJWT is a practical template for this mode.
- This is the most direct route for integration tests and scripted runs.

## Flow 2: Maintenance Program Guided Flow
Use this when you want screen-driven setup with prompts and CRUD maintenance.

### 1) Start from main menu
```cl
CALL PGM(MYLIB/OAUTHMENU)
```

### 2) Option 1: Create keystore through CRTKSD
- Guided entry and validation of keystore values
- Calls CRTKS under the covers
- Can return created file/library to caller context

### 3) Option 2: Work keys through LSTKSRCD
- List existing key records
- F6 to generate a key via GENKEY
- F4 prompt (KAPMT) to choose algorithm
- Option to view public key (SHWPUBKEY)

### 4) Option 3: Maintain JWT configuration through JWTCFGM
- Add/update/delete JWT config rows
- Configure JWTLABEL, keystore, key label, algorithm, claims, expiry
- F4 prompts for:
  - Keystore selection (PRMKSCFG)
  - Key label selection (PRMKSRCD)
  - Algorithm selection (ALGPMT)

### 5) Runtime token generation choices
You can then choose either runtime mode:
- Continue using fully manual JWTGEN calls
- Or lookup by JWTLABEL first (GETJWTCFG), then call JWTGEN with returned values

## Hybrid Flow (Recommended for Production)
This pattern gives maintainability plus runtime simplicity:
1. Use maintenance programs (KSCFGM and JWTCFGM) to curate valid config data.
2. At runtime, call GETJWTCFG with JWTLABEL.
3. Call JWTGEN using returned fields.

Benefits:
- Operators maintain config without code changes.
- Runtime code only needs JWTLABEL plus two program calls.
- Centralized, consistent signing parameters.

## Decision Guide
Choose Manual Flow when:
- You are validating APIs or troubleshooting exact parameter behavior.
- You need ad hoc one-off JWT generation.
- You are writing batch scripts that already own all claim values.

Choose Maintenance Flow when:
- You want guided screens and fewer entry mistakes.
- Business users/admins need to maintain keys and JWT settings.
- You want reusable named JWT profiles (JWTLABEL) managed in tables.

Use Hybrid when:
- You want operational governance via maintenance screens,
- but still keep runtime call paths simple and programmatic.

## Program Mapping at a Glance
| Function | Manual Program Call | Guided Program Path |
|---|---|---|
| Create keystore | CRTKS | OAUTHMENU option 1 -> CRTKSD -> CRTKS |
| Generate key pair | GENKEY | OAUTHMENU option 2 -> LSTKSRCD (F6) -> GENKEY |
| Configure JWT defaults | N/A (manual values each call) | OAUTHMENU option 3 -> JWTCFGM |
| Generate JWT | JWTGEN (all parameters) | GETJWTCFG (by JWTLABEL) + JWTGEN |

## Related References
- docs/jwt-issuance-wrapper-proposal.md
- docs/jwtcfg-active-selection-approach.md
- docs/key-label-prefix-proposal.md
- docs/key-types-roadmap.md
- docs/program-call-map.md
- src/CRTKS.RPGLE
- src/GENKEY.RPGLE
- src/JWTGEN.RPGLE
- src/GETJWTCFG.RPGLE
- src/OAUTHMENU.RPGLE
- src/JWTCFGM.RPGLE
- src/LSTKSRCD.RPGLE
