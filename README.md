# IBM i JWT Generation & Keystore Management System

A comprehensive IBM i RPG-LE application suite for generating JSON Web Tokens (JWTs) and managing cryptographic keystores. Supports RSA and Elliptic Curve (EC) key generation with integrated keystore and JWT configuration management.

## 🚀 Features

### JWT Management
- **Full CRUD JWT Configuration**: Maintain JWT issuer, subject, audience, and algorithm settings
- **Multiple Signature Algorithms**: Support for RS256, RS384, RS512, ES256, ES384, ES512
- **Configurable Expiry**: Set custom token expiration periods (seconds)
- **Keystore Integration**: Link JWT configurations to keystore records
- **Active Configuration Selection**: Retrieve active JWT configuration for token generation

### Keystore Management
- **Keystore Configuration**: Maintain keystore file/library mappings with descriptions
- **Key Generation**: Create RSA (2048-4096 bit) and EC (P-256, P-384, P-521) keys
- **Key Storage**: Secure storage in IBM i *USRSPC keystores
- **Key Listing**: Browse and filter keystore contents by type (RSA/EC/ALL)
- **Public Key Display**: View PEM-encoded public keys for sharing
- **Keystore Creation**: Interactive utility for creating new keystores

### User Interface
- **Subfile-Based Navigation**: Intuitive 5250 green-screen interface
- **Message Subfile Validation**: Real-time field validation with error messages on row 24
- **Function Key Support**: F4 prompting, F5 refresh, F6 add, F10 save, F12 cancel
- **Search & Filter**: Dynamic filtering by label and key type
- **Prompted Fields**: F4 prompting for keystore selection, key labels, and algorithms

## 📁 Project Structure

```
SubfileProgram/
├── src/
│   ├── JWTCFGM.RPGLE      # JWT configuration maintenance (CRUD)
│   ├── JWTCFGD.DSPF       # JWT config display file
│   ├── JWTCFG.SQL         # JWT config table DDL
│   ├── JWTCFGA.SQL        # JWT active config table DDL
│   ├── KSCFGM.RPGLE       # Keystore configuration maintenance
│   ├── KSCFGD.DSPF        # Keystore config display file
│   ├── KSCFG.SQL          # Keystore config table DDL
│   ├── GENKEY.RPGLE       # Master key generation program
│   ├── GENPKAKEY.RPGLE    # RSA key generation
│   ├── GENECCKEY.RPGLE    # Elliptic Curve key generation
│   ├── JWTGEN.RPGLE       # JWT generation engine
│   ├── GETJWTCFG.RPGLE    # Retrieve JWT configuration
│   ├── GETJWACT.RPGLE     # Get active JWT configuration
│   ├── CRTKSD.RPGLE       # Create keystore utility
│   ├── CRTKSD.DSPF        # Keystore creation screen
│   ├── CRTKS.RPGLE        # Keystore creation API wrapper
│   ├── LSTKSRCD.RPGLE     # List keystore records
│   ├── LSTKSRCD.DSPF      # Keystore listing display
│   ├── SHWPUBKEY.RPGLE    # Display public key
│   ├── SHWPUBKEY.DSPF     # Public key display screen
│   ├── EXPRTPEM.RPGLE     # Export key to PEM format
│   ├── DER2PEM.RPGLE      # DER to PEM conversion
│   ├── ECCJWTSIGN.RPGLE   # ECC JWT signing
│   ├── PRMKSCFG.RPGLE     # Prompt for keystore (F4)
│   ├── PRMKSCFG.DSPF      # Keystore prompt display
│   ├── PRMKSRCD.RPGLE     # Prompt for key label (F4)
│   ├── PRMKSRCD.DSPF      # Key label prompt display
│   ├── ALGPMT.RPGLE       # Algorithm selection prompt
│   ├── ALGPMT.DSPF        # Algorithm prompt display
│   ├── KAPMT.RPGLE        # Key algorithm prompt
│   ├── KAPMT.DSPF         # Key algorithm display
│   ├── OAUTHMENU.RPGLE    # OAuth/JWT main menu
│   └── OAUTHMENU.DSPF     # Main menu display
├── docs/
│   ├── technical-guide.md              # Comprehensive technical documentation
│   ├── subfile-message-area-fix.md     # Message subfile troubleshooting
│   ├── program-call-map.md             # Program interaction diagram
│   ├── GENKEY-change-history.txt       # GENKEY development log
│   ├── JWTGEN-change-history.txt       # JWTGEN development log
│   ├── session-notes.md                # Development session notes
│   └── (additional documentation)
├── tools/
│   └── check_dspf_safety.sh            # DDS validation script
├── .github/
│   └── copilot-instructions.md         # GitHub Copilot context
└── README.md
```

## 🔧 Installation & Setup

### Prerequisites

- IBM i system (V7R3 or later recommended)
- RPG-LE compiler
- SQL support enabled
- Digital Certificate Manager (DCM) authorities for keystore operations
- User profile with *SECADM or appropriate Digital Certificate Manager authorities

### DDS Safety Preflight

To catch common fixed-format DDS problems before compile (column alignment, overlong lines, tabs, and broken literals), run:

```bash
bash tools/check_dspf_safety.sh
```

To check a specific display file:

```bash
bash tools/check_dspf_safety.sh src/JWTCFGD.DSPF
```

### Database Setup

Create the required tables using the provided SQL scripts:

```sql
-- JWT Configuration table
RUNSQLSTM SRCFILE(MYLIB/QSQLSRC) SRCMBR(JWTCFG)

-- JWT Active Configuration table
RUNSQLSTM SRCFILE(MYLIB/QSQLSRC) SRCMBR(JWTCFGA)

-- Keystore Configuration table
RUNSQLSTM SRCFILE(MYLIB/QSQLSRC) SRCMBR(KSCFG)
```

### Compilation Steps

Compile display files first, then RPG programs:

```bash
# Display Files
CRTDSPF FILE(MYLIB/JWTCFGD) SRCFILE(MYLIB/QDDSSRC)
CRTDSPF FILE(MYLIB/KSCFGD) SRCFILE(MYLIB/QDDSSRC)
CRTDSPF FILE(MYLIB/CRTKSD) SRCFILE(MYLIB/QDDSSRC)
CRTDSPF FILE(MYLIB/LSTKSRCD) SRCFILE(MYLIB/QDDSSRC)
CRTDSPF FILE(MYLIB/SHWPUBKEY) SRCFILE(MYLIB/QDDSSRC)
CRTDSPF FILE(MYLIB/OAUTHMENU) SRCFILE(MYLIB/QDDSSRC)

# RPG Programs (compile with CRTSQLRPGI for embedded SQL)
CRTSQLRPGI OBJ(MYLIB/JWTCFGM) SRCFILE(MYLIB/QRPGLESRC) +
           COMMIT(*NONE) CLOSQLCSR(*ENDMOD)
           
CRTSQLRPGI OBJ(MYLIB/KSCFGM) SRCFILE(MYLIB/QRPGLESRC) +
           COMMIT(*NONE) CLOSQLCSR(*ENDMOD)
           
CRTBNDRPG PGM(MYLIB/GENKEY) SRCFILE(MYLIB/QRPGLESRC)
CRTBNDRPG PGM(MYLIB/JWTGEN) SRCFILE(MYLIB/QRPGLESRC)
CRTBNDRPG PGM(MYLIB/CRTKSD) SRCFILE(MYLIB/QRPGLESRC)
CRTBNDRPG PGM(MYLIB/LSTKSRCD) SRCFILE(MYLIB/QRPGLESRC)
```

## 🎯 Usage

### Running the Main Menu

```
CALL MYLIB/OAUTHMENU
```

### Program Flow

#### 1. JWT Configuration Maintenance (JWTCFGM)

Manage JWT configurations with full CRUD operations:

- **List View**: Browse all JWT configurations
  - **F5**: Refresh list
  - **F6**: Add new configuration
  - **Option 2**: Change existing configuration
  - **Option 4**: Delete configuration (with confirmation)
  - **Option 5**: View configuration (read-only)
  - **Option 9**: Show public key for associated keystore record

- **Detail Screen**: Add/Change/View JWT settings
  - **JWT Label**: Unique identifier (max 36 chars)
  - **Issuer**: JWT issuer claim (max 128 chars)
  - **Subject**: JWT subject claim (max 128 chars)
  - **Audience**: JWT audience claim (max 256 chars)
  - **Expiry (Sec)**: Token expiration period in seconds
  - **KS File/Library**: Keystore file and library (F4 prompting)
  - **Key Label**: Key label from keystore (F4 prompting)
  - **Algorithm**: JWT signature algorithm (F4 prompting)
  - **F4**: Prompt for valid values
  - **F10**: Save changes
  - **F12**: Cancel

#### 2. Keystore Configuration Maintenance (KSCFGM)

Manage keystore file/library mappings:

- Similar list and detail screens to JWTCFGM
- Maintains keystore description and location
- Links to LSTKSRCD for viewing keystore contents

#### 3. Key Generation (GENKEY)

Generate new cryptographic keys:

```
CALL MYLIB/GENKEY PARM('MYKEYSTORE' 'MYLIB' 'MYKEYLABEL')
```

Parameters:
- Keystore File Name
- Keystore Library
- Key Label (will be prompted for key type and size)

#### 4. JWT Generation (JWTGEN)

Generate a JWT token based on saved configuration:

```
CALL MYLIB/JWTGEN PARM(&JWTLABEL &TOKEN)
```

Parameters:
- Input: JWT Label (from JWTCFG)
- Output: Generated JWT token (returned parameter)

#### 5. List Keystore Records (LSTKSRCD)

Browse keystore contents with filtering:

```
CALL MYLIB/LSTKSRCD PARM('MYKEYSTORE' 'MYLIB')
```

- Filter by key type (RSA/EC/ALL)
- View key details (label, type, size, dates)

#### 6. Show Public Key (SHWPUBKEY)

Display PEM-encoded public key:

```
CALL MYLIB/SHWPUBKEY PARM('MYKEYSTORE' 'MYLIB' 'MYKEYLABEL')
```

## 🏗️ Technical Details

### Key Components

#### JWT Configuration (JWTCFG Table)
- **JWTID**: Unique identifier (auto-increment)
- **JWTLABEL**: User-friendly label
- **ISSUER**: JWT iss claim
- **SUBJECT**: JWT sub claim
- **AUDIENCE**: JWT aud claim
- **EXPIRY_SEC**: Token lifetime in seconds
- **KSFILE/KSLIB/KSLABEL**: Associated keystore record
- **JWALG**: Signature algorithm (RS256, ES256, etc.)
- **CREATETS/CHANGTS**: Audit timestamps

#### Keystore Configuration (KSCFG Table)
- **KSCFGID**: Unique identifier
- **KSDESC**: Keystore description
- **KSFILE**: Keystore file name
- **KSLIB**: Keystore library
- **CREATETS/CHANGTS**: Audit timestamps

#### Message Subfile Pattern

All maintenance programs implement proper message subfile validation:

**DDS Pattern:**
```dds
     A          R MSGSFL                    SFL
     A                                      SFLMSGRCD(24)
     A            MSGKEY                    SFLMSGKEY
     A            PGMQ                      SFLPGMQ
     
     A          R MSGCTL                    SFLCTL(MSGSFL)
     A                                      SFLDSP          ← Unconditional
     A                                      SFLDSPCTL       ← Unconditional
     A                                      SFLINZ
     A  94                                  SFLEND(*MORE)
     A                                      OVERLAY
```

**RPGLE Pattern:**
```rpgle
dcl-proc SetError;
  dcl-pi *n;
    Msg varchar(78) const;
    TargetProc char(10) const options(*nopass);
  end-pi;

  if %passed(TargetProc);
    ProcName = TargetProc;
  else;
    ProcName = 'SHOWDETAIL';  // Procedure that does exfmt
  endif;

  MsgCount += 1;
  snd-msg %trim(Msg) %target(ProcName);
end-proc;
```

### SQL Features Used

- **Embedded SQL**: Direct SQL in RPG programs with `exec sql`
- **Dynamic SQL**: Runtime query building for flexible operations
- **Transaction Control**: `COMMIT(*NONE)` for auto-commit mode
- **Cursor Management**: `CLOSQLCSR(*ENDMOD)` for automatic cursor closing
- **VARCHAR Support**: Variable-length character fields
- **TIMESTAMP**: Automatic audit trail timestamps
- **UNIQUE Constraints**: Ensure data integrity
- **AUTO INCREMENT**: Automatic ID generation

### RPG-LE Best Practices

- **Free-form Syntax**: Modern **FREE RPG coding style
- **Modular Design**: Separate procedures for validation, I/O, data manipulation
- **Qualified Data Structures**: Avoid naming conflicts
- **Template Patterns**: Reusable data structure definitions
- **Error Handling**: Comprehensive SQLSTATE checking
- **API Integration**: Proper use of IBM i cryptographic APIs
- **Parameter Passing**: Options(*nopass) for flexible procedure calls
- **Indicator Management**: Named indicators in indicator data structure

## 🔐 Security Considerations

- **Keystore Access**: Requires appropriate Digital Certificate Manager authorities
- **Key Protection**: Keys stored securely in IBM i *USRSPC keystores
- **Audit Trail**: All configuration changes timestamp-tracked
- **Authority Checking**: Programs should run with appropriate authority
- **PEM Export**: Public keys only; private keys never exported
- **JWT Expiry**: Configurable expiration prevents indefinite token validity

## 📚 Documentation

- **[Technical Guide](docs/technical-guide.md)**: Comprehensive architecture and design documentation
- **[Message Subfile Fix](docs/subfile-message-area-fix.md)**: Troubleshooting guide for message subfile validation
- **[Program Call Map](docs/program-call-map.md)**: Visual program interaction diagram
- **[Session Notes](docs/session-notes.md)**: Development session history

## 🔍 Code Highlights

### Dynamic Validation with Message Subfile

```rpgle
dcl-proc ValidateDetail;
  dcl-s Valid ind inz(*on);

  ResetErrorAttrs();
  
  if %trimr(DIJWTLBL) = '';
    ATTRLBL = ATTR_RED_RI;
    SetError('JWT Label is required.');
    if Valid;
      CSRROW = 4;
      CSRCOL = 12;
    endif;
    Valid = *off;
  endif;

  if %trimr(DISSUER) = '';
    ATTRISS = ATTR_RED_RI;
    SetError('Issuer is required.');
    if Valid;
      CSRROW = 5;
      CSRCOL = 12;
    endif;
    Valid = *off;
  endif;

  return Valid;
end-proc;
```

### F4 Prompting Pattern

```rpgle
if dspf_info.pressedKey = KEY_F4;
  select;
    when %trimr(FLD) = 'DIKSFILE' or %trimr(FLD) = 'DIKSLIB';
      CallPRMKSCFG(DIKSFILE : DIKSLIB);
      CSRROW = 9;
      CSRCOL = 12;
    when %trimr(FLD) = 'DIKSLBL';
      CallPRMKSRCD(DIKSFILE : DIKSLIB : DIKSLBL);
      CSRROW = 10;
      CSRCOL = 12;
    when %trimr(FLD) = 'DIALG';
      CallALGPMT(DIALG);
      CSRROW = 11;
      CSRCOL = 12;
  endsl;
  iter;
endif;
```

### SQL CRUD Operations

```rpgle
// Insert with timestamp
exec sql
  INSERT INTO JWTCFG
     (JWTLABEL, ISSUER, SUBJECT, AUDIENCE, EXPIRY_SEC,
      KSFILE, KSLIB, KSLABEL, JWALG,
      CREATETS, CHANGTS)
    VALUES (:WRow.JwtLabel,  :WRow.Issuer,  :WRow.Subject,
      :WRow.Audience,  :WRow.ExpirySec, :WRow.KsFile,
      :WRow.KsLib,     :WRow.KsLabel, :WRow.JwtAlg,
      CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

// Update with timestamp
exec sql
  UPDATE JWTCFG
     SET JWTLABEL   = :WRow.JwtLabel,
         ISSUER     = :WRow.Issuer,
         CHANGTS    = CURRENT_TIMESTAMP
   WHERE JWTID      = :WRow.JwtId;
```

## 🐛 Troubleshooting

### Message Subfile Not Displaying

If validation error messages don't appear on row 24:

1. **Check DDS**: Ensure SFLDSP/SFLDSPCTL are unconditional (no indicators)
2. **Check Target**: Verify `snd-msg %target(ProcName)` targets the procedure doing `exfmt`
3. **Check SFLPGMQ**: Must be set to program/procedure name
4. **See Documentation**: [Message Subfile Fix Guide](docs/subfile-message-area-fix.md)

### Keystore Access Issues

If you encounter authority errors:

1. Check Digital Certificate Manager authorities
2. Verify *USRSPC authority for keystore file/library
3. Ensure user profile has *SECADM or appropriate special authority

### Compilation Errors

1. Verify all display files compiled before RPG programs
2. Check SQL options: `COMMIT(*NONE)` and `CLOSQLCSR(*ENDMOD)`
3. Ensure tables exist before compiling programs with embedded SQL

## 🤝 Contributing

This is an internal project. For questions or issues, contact the development team.

## 📝 License

Copyright © 2026 Jack Henry & Associates, Inc. All rights reserved.

## 🔮 Future Enhancements

- [ ] Additional JWT algorithms (PS256, PS384, PS512)
- [ ] JWT validation utilities
- [ ] Key rotation management
- [ ] Batch JWT generation
- [ ] Integration with OAuth 2.0 flows
- [ ] REST API wrapper for JWT generation
- [ ] Key expiration tracking and alerts


