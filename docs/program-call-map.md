# Program Call Relationships — JWT Key Management Suite

## Legend
- **→ calls →** : program-to-program call (EXTPGM)
- **Interactive** : has a display file; user-facing
- **Batch/API** : no display file; called programmatically

---

## Program Inventory

| Program | Type | Function |
|---------|------|----------|
| **OAUTHMENU** | Interactive | Main menu/launcher for keystore and JWT maintenance flows. Routes users to CRTKSD, LSTKSRCD, JWTCFGM, and KSCFGM. |
| **JWTCFGM** | Interactive | Full CRUD maintenance for the JWTCFG table. List screen with load-all subfile; detail screen for Add/Change/View/Delete of JWT configuration records (issuer, subject, audience, keystore location, JWT algorithm, expiry). |
| **KSCFGM** | Interactive | Full maintenance for KSCFG. List + Change/Delete/View, `A=Make Active`, `9=Work Keys`, and `F6=Create Keystore` via CRTKSD with optional write-to-KSCFG registration. |
| **LSTKSRCD** | Interactive | Lists all key records in a keystore (*KEYFIL) via `Qc3RetrieveKeyStoreRecords`. Supports viewing public keys, generating new keys, and filtering by key type. |
| **ALGPMT** | Interactive (prompt) | JWT algorithm selection subfile (RS256, RS384, RS512, PS256…ES512, EdDSA). Returns the selected JWT algorithm identifier. Called from JWTCFGM F4 on the JWT Alg field. |
| **KAPMT** | Interactive (prompt) | GENKEY key algorithm selection subfile (RSA512, RSA2048, ECC_P256…ECC_ED44). Returns the selected GENKEY key algorithm string. Called from LSTKSRCD F4 on the Generate Key panel. |
| **PRMKSCFG** | Interactive (prompt) | KSCFG selection prompt. Returns selected keystore file/library from KSCFG. Called from JWTCFGM F4 on KS File/Library fields. |
| **PRMKSRCD** | Interactive (prompt) | Key label selection subfile. Lists all records in a given keystore and returns the selected label. Called from JWTCFGM F4 on the Key Label field. |
| **GENKEY** | Batch/API | Generates an RSA or ECC key pair directly into a keystore using `Qc3GenKeyRecord`. Called from LSTKSRCD after the user provides a label and key algorithm. |
| **SHWPUBKEY** | Interactive | Displays a public key as PEM lines in a subfile. Extracts the key via `Qc3ExtractPublicKey`, converts DER→PEM, and optionally exports to IFS (F6). |
| **EXPRTPEM** | Batch/API | Writes a PEM string to the IFS using `QSYS2.IFS_WRITE_UTF8`. Called from SHWPUBKEY when the user presses F6=Export. |
| **JWTGEN** | Batch/API | Generates a signed JWT token using a private key from a keystore. Supports RSA-PKCS1, RSA-PSS, ECDSA, and EdDSA algorithms. |
| **TESTJWT** | Batch/API | Test wrapper that calls JWTGEN with sample values and displays the resulting JWT token. |
| **CRTKS** | Batch/API | Creates an IBM i keystore file (*KEYFIL) using `Qc3CreateKeyStore`. Run once to create the keystore before generating keys. |
| **CRTKSD** | Interactive | Screen driver for CRTKS. Collects keystore file name, library, master key ID, description, authority, optional function, and optional write-to-KSCFG flag; validates input; calls CRTKS; returns created values to callers when passed. |
| **GENPKAKEY** | Batch/API | Generates an RSA key pair using `Qc3GenPKAKeyPair` and writes both keys to a keystore via `Qc3WriteKeyRecord`. Older RSA-only counterpart to GENKEY. |
| **GENECCKEY** | Batch/API | Generates an ECC key pair using `Qc3GenECCKeyPair`. Older ECC-only counterpart to GENKEY. |
| **ECCJWTSIGN** | Batch/API | Generates an ES256 JWT using ECDSA P-256 + SHA-256. Standalone signer program. |
| **DER2PEM** | Batch/API | Converts DER-encoded binary key data to PEM format (Base64 + header/footer). |
| **SUBFLPGM** | Interactive | Demo employee maintenance subfile program (SQL-driven). Unrelated to JWT/keystore programs. |

---

## Call Graph

```
OAUTHMENU
  ├─→ CRTKSD            (option 1 = Create Keystore)
  ├─→ LSTKSRCD          (option 2 = List Keystore Records)
  ├─→ JWTCFGM           (option 3 = JWT Config Maintenance)
  └─→ KSCFGM            (option 4 = Work With Keystores)

CRTKSD
  └─→ CRTKS

TESTJWT
  └─→ JWTGEN

KSCFGM
  ├─→ CRTKSD            (F6 = Create Keystore; conditional insert to KSCFG)
  └─→ LSTKSRCD          (option 9 = Work Keys)

JWTCFGM
  ├─→ SHWPUBKEY          (option 9 = Show Public Key)
  │     └─→ EXPRTPEM     (F6 = Export PEM to IFS)
  ├─→ PRMKSCFG           (F4 on KS File / KS Library fields)
  ├─→ PRMKSRCD           (F4 on Key Label field)
  └─→ ALGPMT             (F4 on JWT Alg field)

LSTKSRCD
  ├─→ GENKEY             (F6 = Generate New Key)
  ├─→ KAPMT              (F4 on Algorithm field in Generate Key panel)
  └─→ SHWPUBKEY          (option 1 = Show Public Key)
        └─→ EXPRTPEM     (F6 = Export PEM to IFS)
```

---

## Prompt Program Call Map

| Prompt Program | Called From | Trigger |
|----------------|-------------|---------|
| **ALGPMT** | **JWTCFGM** | F4 on JWT Alg field |
| **KAPMT** | **LSTKSRCD** | F4 on Algorithm field in Generate Key panel |
| **PRMKSCFG** | **JWTCFGM** | F4 on KS File / KS Library fields |
| **PRMKSRCD** | **JWTCFGM** | F4 on Key Label field |

---

## Standalone Programs (no callers within this suite)

| Program | Notes |
|---------|-------|
| **GENPKAKEY** | Older RSA key generator; superseded by GENKEY |
| **GENECCKEY** | Older ECC key generator; superseded by GENKEY |
| **ECCJWTSIGN** | Standalone ES256 JWT signer |
| **DER2PEM** | Utility; procedures also used inline by SHWPUBKEY and GENPKAKEY |
| **SUBFLPGM** | Unrelated demo program |

---

## Recent Behavioral Updates

- **CRTKSD** now supports optional outputs (`CreatedFile`, `CreatedLib`, `CreatedFunc`, `WriteToCfg`) so callers can decide whether to register in KSCFG.
- **CRTKSD** now performs optional KSCFG registration when `WriteToCfg='Y'`; this keeps create + optional register behavior centralized.
- **KSCFGM** now delegates optional registration to CRTKSD and no longer performs a separate insert path.
- **LSTKSRCD** now follows the same AID-key and message-subfile patterns used by JWTCFGM/KSCFGM.
- **LSTKSRCD** empty-subfile handling was hardened to avoid READC/device/session errors when no rows are loaded.

---

## Display Files (DSPF)

| Display File | Used By | Purpose |
|--------------|---------|---------|
| **OAUTHMENU.DSPF** | OAUTHMENU | Main menu launcher for keystore/JWT workflows |
| **ALGPMT.DSPF** | ALGPMT | JWT algorithm selection subfile (132-wide) |
| **KAPMT.DSPF** | KAPMT | Key algorithm selection subfile (132-wide) |
| **CRTKSD.DSPF** | CRTKSD | Create Keystore single-screen input form |
| **KSCFGD.DSPF** | KSCFGM | KSCFG list + detail + delete + message panels |
| **JWTCFGD.DSPF** | JWTCFGM | JWT config list + detail + delete panels |
| **LSTKSRCD.DSPF** | LSTKSRCD | Keystore record list + generate key panel |
| **PRMKSCFG.DSPF** | PRMKSCFG | KSCFG selection prompt subfile |
| **PRMKSRCD.DSPF** | PRMKSRCD | Key label selection prompt subfile |
| **SHWPUBKEY.DSPF** | SHWPUBKEY | PEM public key display subfile |

---

## Database Objects (SQL)

| Object | Type | Used By |
|--------|------|---------|
| **JWTCFG** | Table | JWTCFGM (full CRUD), JWTGEN (read) |
| **KSCFG** | Table | KSCFGM (full CRUD + activate) |

*Scripts: `src/JWTCFG.SQL`, `src/KSCFG.SQL`*

---

## Related Documentation

- docs/manual-vs-maintenance-flow.md
- docs/jwt-issuance-wrapper-proposal.md
- docs/jwtcfg-active-selection-approach.md
- docs/key-label-prefix-proposal.md
- docs/key-types-roadmap.md

---

*Last updated: April 11, 2026*
