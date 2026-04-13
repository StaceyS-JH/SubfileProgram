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
# RPG-LE Subfile Program with SQL Integration

This project demonstrates a comprehensive RPG-LE subfile program that integrates SQL for database operations on IBM i systems. The program provides employee maintenance functionality with search capabilities and basic CRUD operations.

## 🚀 Features

- **Page-at-a-Time Subfile**: Memory-efficient paging with 14 records per page
- **Real-time Lastname Filter**: Filter displayed records instantly using F5
- **Dual Search System**: Initial search + real-time subfile filtering
- **SQL Integration**: Uses embedded SQL with OFFSET/FETCH for pagination
- **Navigation Controls**: Page Up/Down keys for seamless browsing
- **Search Functionality**: Filter employees by department and last name  
- **CRUD Operations**: Create, Read, Update, and Delete employee records
- **Modern RPG-LE**: Uses free-form RPG syntax and structured programming
- **Performance Optimized**: Loads only current page data for large datasets
- **Error Handling**: Comprehensive SQL error handling and user feedback

## 📁 Project Structure

```
SubfileProgram/
├── src/
│   ├── SUBFLPGM.RPGLE    # Main RPG-LE program
│   └── SUBFLSF.DSPF      # Display file (DDS)
├── docs/
│   └── (documentation files)
├── .github/
│   └── copilot-instructions.md
└── README.md
```

## 🔧 Installation & Setup

### Prerequisites

- IBM i system with RPG-LE compiler
- SQL support enabled
- EMPLOYEE table in your library (see Database Setup below)

### DDS Safety Preflight

To catch common fixed-format DDS problems before compile (column alignment,
overlong lines, tabs, and broken literals), run:

```bash
bash tools/check_dspf_safety.sh
```

To check only one display file:

```bash
bash tools/check_dspf_safety.sh src/TESTJWTCFG.DSPF
```

### Database Setup

Create the EMPLOYEE table with the following structure:

```sql
CREATE TABLE EMPLOYEE (
    EMPNO DECIMAL(5,0) NOT NULL PRIMARY KEY,
    FIRSTNAME VARCHAR(20) NOT NULL,
    LASTNAME VARCHAR(20) NOT NULL,
    DEPT CHAR(3) NOT NULL,
    SALARY DECIMAL(9,2) NOT NULL
);

-- Sample data
INSERT INTO EMPLOYEE VALUES 
(12345, 'John', 'Smith', 'IT', 65000.00),
(12346, 'Jane', 'Doe', 'HR', 58000.00),
(12347, 'Bob', 'Johnson', 'ACC', 52000.00),
(12348, 'Alice', 'Brown', 'IT', 72000.00),
(12349, 'Charlie', 'Wilson', 'MKT', 48000.00);
```

### Compilation Steps

1. **Compile the Display File:**
```
CRTDSPF FILE(MYLIB/SUBFLSF) SRCFILE(MYLIB/QDDSSRC) SRCMBR(SUBFLSF)
```

2. **Compile the RPG Program:**
```
CRTRPGMOD MODULE(MYLIB/SUBFLPGM) SRCFILE(MYLIB/QRPGLESRC) SRCMBR(SUBFLPGM)
CRTPGM PGM(MYLIB/SUBFLPGM) MODULE(MYLIB/SUBFLPGM) SRCFILE(MYLIB/QSRVSRC)
```

## 🎯 Usage

### Running the Program

```
CALL MYLIB/SUBFLPGM
```

### Program Flow

1. **Search Screen**: Enter search criteria (optional)
   - Department: 3-character department code
   - Last Name: Partial or full last name
   - Press Enter to search, F3 to exit

2. **Subfile Display**: Review employee records (14 per page)
   - **Filter Field**: Type lastname filter and press F5 to apply
   - Use options 2, 4, or 5 on employees
   - Page Up/Page Down to navigate between pages
   - F5 to refresh with new filter
   - Press Enter to process options
   - F3 to exit, F12 to return to search

### Available Options

- **F5 (Filter)**: Apply lastname filter to current results
- **Option 2 (Change)**: Increases employee salary by 5%
- **Option 4 (Delete)**: Removes employee from database  
- **Option 5 (Display)**: Shows detailed employee information

## 🏗️ Technical Details

### Key Components

#### Display File (SUBFLSF.DSPF)
- **SFL**: Subfile record format for employee data
- **SFLCTL**: Subfile control format with function keys
- **SFLHEAD**: Search criteria input screen
- **SFLFOOTER**: Function key instructions
- **SFLMSG**: Message display area

#### RPG Program (SUBFLPGM.RPGLE)
- **InitializePaging()**: Calculates total records and pages with filters
- **LoadCurrentPage()**: Loads specific page using SQL OFFSET/FETCH
- **BuildFilterCondition()**: Combines search and filter criteria
- **GetSearchCriteria()**: Handles search screen input
- **DisplaySubfilePage()**: Manages page display with filter field
- **ProcessPageInput()**: Handles options, navigation, and F5 filtering
- **UpdateEmployee()**: SQL update operations
- **DeleteEmployee()**: SQL delete operations  
- **DisplayEmployee()**: SQL select for detailed display

### SQL Features Used

- **Dynamic WHERE Clauses**: Runtime filter combination and building
- **Pagination**: OFFSET and FETCH FIRST for efficient page loading
- **Record Counting**: COUNT(*) queries with combined filter conditions
- **Dynamic Cursors**: Runtime cursor creation with positioning
- **Prepared Statements**: Dynamic SQL execution with parameters
- **Multiple Filter Layers**: Search criteria + real-time filtering
- **Error Handling**: SQLCODE checking for robust error management
- **Calculated Fields**: CASE statements for derived data (STATUS field)
- **Pattern Matching**: LIKE operator for flexible searching

### RPG-LE Best Practices

- **Free-form Syntax**: Modern RPG coding style
- **Modular Design**: Separate procedures for different functions
- **Template Data Structures**: Reusable data definitions
- **Proper Initialization**: Clear variable and indicator management
- **Error Messaging**: User-friendly error feedback

## 🔍 Code Highlights

### Dynamic Filter Building
```rpg
P BuildFilterCondition B
D BuildFilterCondition PI           100A   VARYING

  WhereClause = '1=1';
  
  // Add department filter from search
  IF SRCDEPT <> '';
    WhereClause += ' AND DEPT = ''' + %TRIM(SRCDEPT) + '''';
  ENDIF;
  
  // Add lastname filters (search + real-time filter)
  IF SRCLNAME <> '';
    WhereClause += ' AND UPPER(LASTNAME) LIKE ''%' + 
                   %UPPER(%TRIM(SRCLNAME)) + '%''';
  ENDIF;
  
  IF CURRENTFILTER <> '';
    WhereClause += ' AND UPPER(LASTNAME) LIKE ''%' + 
                   %UPPER(%TRIM(CURRENTFILTER)) + '%''';
  ENDIF;
  
  RETURN WhereClause;
P BuildFilterCondition E
```

### Dynamic SQL with Combined Filters
```rpg
SQLSTMT = 'SELECT EMPNO, FIRSTNAME, LASTNAME, DEPT, SALARY, ' +
          'CASE WHEN SALARY >= 50000 THEN ''ACTIVE'' ' +
          'ELSE ''REVIEW'' END AS STATUS ' +
          'FROM EMPLOYEE WHERE ' + FilterCondition + ' ' +
          'ORDER BY LASTNAME, FIRSTNAME ' +
          'OFFSET ? ROWS FETCH FIRST ? ROWS ONLY';
```

### Filter and Navigation Handling
```rpg
SELECT;
  WHEN *IN05; // F5 - Refresh with filter
    IF %TRIM(FILTER) <> CURRENTFILTER;
      FILTERCHANGED = *ON;
      RELOAD = *ON;
    ENDIF;
  WHEN *IN25; // Page Down
    IF PAGENUM < TOTALPAGES;
      PAGENUM += 1;
    ENDIF;
  WHEN *IN26; // Page Up
    IF PAGENUM > 1;
      PAGENUM -= 1;
    ENDIF;
ENDSL;
```

### Total Record Count for Pagination
```rpg
EXEC SQL SELECT COUNT(*) INTO :TOTALRECS
  FROM EMPLOYEE
  WHERE (DEPT = :SRCDEPT OR :SRCDEPT = '')
    AND (UPPER(LASTNAME) LIKE '%' || UPPER(:SRCLNAME) || '%' 
         OR :SRCLNAME = '');

TOTALPAGES = %DIV(TOTALRECS - 1 : PAGESIZE) + 1;
```

## 🛠️ Customization

### Adding New Fields
1. Update the EMPLOYEE table structure
2. Modify the EmpDS data structure in the RPG program
3. Update the display file to include new fields
4. Adjust SQL statements to handle new columns

### Additional Options
- Add new option processing in the ProcessInput() procedure
- Create new procedures for complex operations
- Implement additional validation logic

### Enhanced Search
- Add more search criteria fields to SFLHEAD
- Modify the cursor SQL to include new WHERE conditions
- Update LoadSubfile() procedure accordingly

## 📚 Resources

- [IBM RPG-LE Reference](https://www.ibm.com/docs/en/i/7.4?topic=languages-ile-rpg)
- [IBM SQL for i Reference](https://www.ibm.com/docs/en/i/7.4?topic=i-sql)
- [DDS Reference](https://www.ibm.com/docs/en/i/7.4?topic=specifications-dds-concepts)

## 🤝 Contributing

Feel free to enhance this program by:
- Adding more sophisticated search options
- Implementing data validation
- Adding audit trail functionality
- Creating additional maintenance screens

## 📄 License

This project is provided as an educational example for IBM i development.

---

*Generated by GitHub Copilot - September 30, 2025*