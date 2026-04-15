# Upload Tools for IBM i

This directory contains batch upload scripts for transferring source files to IBM i.

## Available Scripts

### 1. upload-to-ibmi.bat (Windows Batch)
**Best for:** Windows Command Prompt users

```cmd
upload-to-ibmi.bat HOSTNAME USERNAME LIBRARY
```

Example:
```cmd
upload-to-ibmi.bat PUB400.COM MYUSER DEVLIB
```

### 2. upload-to-ibmi.sh (Bash)
**Best for:** Git Bash, WSL, Linux, macOS users

```bash
chmod +x upload-to-ibmi.sh
./upload-to-ibmi.sh HOSTNAME USERNAME LIBRARY
```

Example:
```bash
./upload-to-ibmi.sh pub400.com myuser devlib
```

### 3. upload-to-ibmi.ps1 (PowerShell)
**Best for:** Modern Windows with PowerShell

```powershell
.\upload-to-ibmi.ps1 -Host HOSTNAME -User USERNAME -Library LIBRARY
```

Example:
```powershell
.\upload-to-ibmi.ps1 -Host PUB400.COM -User MYUSER -Library DEVLIB
```

Optional password parameter (not recommended for security):
```powershell
.\upload-to-ibmi.ps1 -Host PUB400.COM -User MYUSER -Library DEVLIB -Password secret
```

## What Gets Uploaded

### RPGLE Files → QRPGLESRC
- JWTCFGM, KSCFGM, GENKEY, GENPKAKEY, GENECCKEY
- JWTGEN, GETJWTCFG, GETJWACT
- CRTKSD, CRTKS, LSTKSRCD, SHWPUBKEY
- EXPRTPEM, DER2PEM, ECCJWTSIGN
- PRMKSCFG, PRMKSRCD, ALGPMT, KAPMT
- OAUTHMENU
- TESTGETCFG, TESTJWACT, TESTJWT, TESTJWTCFG

### DSPF Files → QDDSSRC
- JWTCFGD, KSCFGD, CRTKSD, LSTKSRCD
- SHWPUBKEY, PRMKSCFG, PRMKSRCD
- ALGPMT, KAPMT, OAUTHMENU, TESTJWTCFG

### SQL Files → QSQLSRC
- JWTCFG, JWTCFGA, KSCFG

## Prerequisites

### On IBM i (before running scripts):

1. **Create target library:**
   ```
   CRTLIB LIB(YOURLIB) TEXT('JWT Keystore System')
   ```

2. **Create source physical files:**
   ```
   CRTSRCPF FILE(YOURLIB/QRPGLESRC) RCDLEN(112) TEXT('RPG Source')
   CRTSRCPF FILE(YOURLIB/QDDSSRC) RCDLEN(112) TEXT('DDS Source')
   CRTSRCPF FILE(YOURLIB/QSQLSRC) RCDLEN(112) TEXT('SQL Source')
   ```

3. **Verify FTP server is running:**
   ```
   STRTCPSVR SERVER(*FTP)
   ```

4. **Check your user profile has authority** to the library and source files

### On Your PC:

- FTP client must be available (built into Windows/Linux/Mac)
- Navigate to the `tools/` directory before running scripts
- Scripts expect source files in `../src/` directory

## After Upload

### Verify Upload
```
WRKMBRPDM FILE(YOURLIB/QRPGLESRC)
WRKMBRPDM FILE(YOURLIB/QDDSSRC)
WRKMBRPDM FILE(YOURLIB/QSQLSRC)
```

### Compile in This Order

1. **Create SQL tables:**
   ```
   RUNSQLSTM SRCFILE(YOURLIB/QSQLSRC) SRCMBR(JWTCFG)
   RUNSQLSTM SRCFILE(YOURLIB/QSQLSRC) SRCMBR(JWTCFGA)
   RUNSQLSTM SRCFILE(YOURLIB/QSQLSRC) SRCMBR(KSCFG)
   ```

2. **Compile display files:**
   ```
   CRTDSPF FILE(YOURLIB/JWTCFGD) SRCFILE(YOURLIB/QDDSSRC)
   CRTDSPF FILE(YOURLIB/KSCFGD) SRCFILE(YOURLIB/QDDSSRC)
   CRTDSPF FILE(YOURLIB/CRTKSD) SRCFILE(YOURLIB/QDDSSRC)
   ... (compile all DSPF files)
   ```

3. **Compile RPG programs with SQL:**
   ```
   CRTSQLRPGI OBJ(YOURLIB/JWTCFGM) SRCFILE(YOURLIB/QRPGLESRC) +
              COMMIT(*NONE) CLOSQLCSR(*ENDMOD)
   CRTSQLRPGI OBJ(YOURLIB/KSCFGM) SRCFILE(YOURLIB/QRPGLESRC) +
              COMMIT(*NONE) CLOSQLCSR(*ENDMOD)
   ```

4. **Compile RPG programs without SQL:**
   ```
   CRTBNDRPG PGM(YOURLIB/GENKEY) SRCFILE(YOURLIB/QRPGLESRC)
   CRTBNDRPG PGM(YOURLIB/CRTKSD) SRCFILE(YOURLIB/QRPGLESRC)
   ... (compile remaining programs)
   ```

## Troubleshooting

### "Connection refused" or "Unknown host"
- Verify IBM i hostname/IP is correct
- Check FTP server is running: `NETSTAT *CNN` on IBM i
- Ping the IBM i system: `ping hostname`

### "Login incorrect"
- Verify username and password
- Check user profile is not disabled
- Ensure you have \*CHANGE authority to the library

### "File not found"
- Create source files first (see Prerequisites)
- Verify library name spelling
- Check source files exist: `DSPFD FILE(YOURLIB/QRPGLESRC)`

### Files upload but appear corrupted
- Ensure ASCII mode is used (scripts handle this)
- Check CCSID conversion settings
- Verify RCDLEN(112) on source files

### PowerShell "Execution Policy" error
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Alternative: Manual ACS Method

If scripts don't work, use IBM ACS File Transfer:
1. Launch ACS → File Transfer
2. Connect to IBM i
3. Select all files in `src/`
4. Drag to appropriate source files on IBM i
5. ACS handles ASCII/EBCDIC conversion automatically

## DDS Validation

Before uploading, validate DDS syntax:
```bash
bash check_dspf_safety.sh
```

This catches column misalignment and formatting issues.
