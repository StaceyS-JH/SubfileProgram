# Subfile Message Area Fix - Resolution Summary

**Date:** April 13, 2026  
**Programs Affected:** JWTCFGM, KSCFGM, CRTKSD, LSTKSRCD  
**Issue:** Message subfile displays "More..." or "Bottom" on line 25, but line 24 (message text) remains blank

---

## Problem Description

All maintenance programs with message subfile validation were experiencing the same symptom: validation errors triggered the message subfile indicators correctly (line 25 showed "More..." or "Bottom"), but the actual error message text on line 24 remained blank.

### Symptoms Observed
- F10 (Save) with invalid fields triggered validation
- Line 25 showed "More..." when multiple errors existed
- Line 25 showed "Bottom" with single error
- **Line 24 (SFLMSGRCD) was consistently blank** - no message text displayed
- Field highlighting (red reverse-image) worked correctly
- No program crashes or SQL errors

---

## Root Cause Analysis

The issue had **two independent root causes**, both required correction:

### Root Cause #1: Conditional SFLDSP Keywords in DDS

**Problem:**  
Message subfile control records used conditional indicators on SFLDSP/SFLDSPCTL keywords:

```dds
     A          R JWTMSGCTL                 SFLCTL(JWTMSGSFL)
     A  95                                  SFLDSP          ← WRONG
     A  95                                  SFLDSPCTL       ← WRONG
```

**Why It Failed:**  
The message subfile mechanism automatically manages display based on what's in the program message queue. Conditioning these keywords on an indicator (95) prevented the display file from properly accessing the message queue, even when messages existed.

**Reference:**  
Analysis of ERMS950.SQLRPGLE (working example from member:/R4SRCJHA) showed unconditional SFLDSP/SFLDSPCTL:

```dds
     A          R MSGCTL                    SFLCTL(MSGSFL)
     A                                      OVERLAY
     A                                      SFLDSP          ← No indicator
     A                                      SFLDSPCTL       ← No indicator
```

### Root Cause #2: Incorrect Message Queue Targeting

**Problem:**  
When `snd-msg` is called from within a **procedure** without an explicit target, messages go to the procedure's private queue, not the program-level queue.

**Call Stack Example (JWTCFGM):**
```
Main (program level)
  └─ ShowDetail (does exfmt JWTDTL - display reads from THIS queue)
      └─ ValidateDetail
          └─ SetError (sends message with snd-msg)
```

**Original Code:**
```rpgle
dcl-proc SetError;
  MsgCount += 1;
  snd-msg %trim(Msg);           // Goes to SetError's private queue
end-proc;
```

**Why It Failed:**  
The display file (via `SFLPGMQ`) reads messages from the queue of the procedure performing the I/O operation (`exfmt`). In JWTCFGM, that's `ShowDetail`. Messages sent from `SetError` without a target stayed in SetError's private queue where the display file couldn't find them.

**Attempted Solutions That Failed:**
- `snd-msg %target(*)` - Same issue
- `snd-msg %target(*caller)` - Targeted ValidateDetail, not ShowDetail
- `snd-msg %target(PGMQ)` where `PGMQ=Psds.PgmName` - Caused CPF2479 crash
- `snd-msg %target(*self : 3)` - Offset calculation fragile with PEP

---

## Solution Implemented

### Fix #1: Make SFLDSP/SFLDSPCTL Unconditional (DDS)

**Files Changed:**
- src/JWTCFGD.DSPF
- src/KSCFGD.DSPF
- src/CRTKSD.DSPF
- src/LSTKSRCD.DSPF

**Change:**
```dds
     A          R JWTMSGCTL                 SFLCTL(JWTMSGSFL)
     A                                      SFLDSP          ← No indicator
     A                                      SFLDSPCTL       ← No indicator
     A                                      SFLINZ
     A  94                                  SFLEND(*MORE)
     A                                      SFLSIZ(10) SFLPAG(1)
     A                                      OVERLAY
     A            PGMQ                      SFLPGMQ
```

**RPGLE Changes:**
- Removed `MsgSflDsp` (indicator 95) from Ind structure
- Removed all assignments to `MsgSflDsp` before `write MSGCTL`

### Fix #2: Target Correct Procedure Queue (RPGLE)

**Enhanced SetError Signature:**
```rpgle
dcl-pr SetError;
  Msg varchar(78) const;
  TargetProc char(10) const options(*nopass);
end-pr;
```

**Updated Implementation:**
```rpgle
//==============================================================
// Procedure: SetError
// Sends an error message to the program message queue.
// Parameters:
//   Msg        - Error message text (max 78 chars)
//   TargetProc - Optional procedure name that does the exfmt
// The message must target the procedure that issues the exfmt
// I/O operation, as the display file reads messages from that
// procedure's queue via SFLPGMQ.
//==============================================================
dcl-proc SetError;

  dcl-pi *n;
    Msg varchar(78) const;
    TargetProc char(10) const options(*nopass);
  end-pi;

  dcl-s ProcName char(10);

  // Default to appropriate procedure if not specified
  if %passed(TargetProc);
    ProcName = TargetProc;
  else;
    ProcName = 'SHOWDETAIL';  // Or 'MAIN' for single-screen programs
  endif;

  MsgCount += 1;
  snd-msg %trim(Msg) %target(ProcName);

end-proc SetError;
```

**Program-Specific Defaults:**
- **JWTCFGM**: `'SHOWDETAIL'` - Detail screen uses ShowDetail procedure
- **KSCFGM**: `'SHOWDETAIL'` - Detail screen uses ShowDetail procedure  
- **CRTKSD**: `'MAIN'` - Single-screen program, Main does the exfmt
- **LSTKSRCD**: `'MAIN'` - List screen, Main does the exfmt

---

## Programs Updated

### 1. JWTCFGM.RPGLE & JWTCFGD.DSPF
**Changes:**
- DDS: Removed indicator 95 from SFLDSP/SFLDSPCTL
- RPGLE: Added optional TargetProc parameter to SetError, defaults to 'SHOWDETAIL'
- Removed MsgSflDsp indicator (2 assignments removed)

### 2. KSCFGM.RPGLE & KSCFGD.DSPF  
**Changes:**
- DDS: Removed indicator 95 from SFLDSP/SFLDSPCTL
- RPGLE: Changed from `%target(PGMQ)` to `%target(ProcName)`, defaults to 'SHOWDETAIL'
- Removed MsgSflDsp indicator (2 assignments removed)

### 3. CRTKSD.RPGLE & CRTKSD.DSPF
**Changes:**
- DDS: Removed indicator 95 from SFLDSP
- RPGLE: Changed from `%target(*caller)` to `%target(ProcName)`, defaults to 'MAIN'
- Removed MsgSflDsp indicator (2 assignments removed)

### 4. LSTKSRCD.RPGLE & LSTKSRCD.DSPF
**Changes:**
- DDS: Removed indicator 95 from SFLDSP/SFLDSPCTL  
- RPGLE: Changed from `%target(*caller)` to `%target(ProcName)`, defaults to 'MAIN'
- Removed MsgShow indicator (3 assignments removed)

---

## Validation & Testing

**Test Scenario:**
1. Call maintenance program (e.g., JWTCFGM)
2. Press F6 (Add new record)
3. Leave 2+ required fields blank
4. Press F10 (Save)

**Expected Results:**
- ✓ Line 24 displays first validation error message text
- ✓ Line 25 shows "More..." if multiple errors exist
- ✓ Line 25 shows "Bottom" if only one error
- ✓ Invalid fields display in red reverse-image
- ✓ Cursor positioned to first error field

**Verification:**
All programs compile cleanly with no errors.

---

## Pattern for Future Programs

When implementing message subfile validation in new programs:

### DDS Pattern
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
     A                                      SFLSIZ(10) SFLPAG(1)
     A                                      OVERLAY
     A            PGMQ                      SFLPGMQ
```

### RPGLE Pattern

**SetError Procedure:**
```rpgle
dcl-proc SetError;
  dcl-pi *n;
    Msg varchar(78) const;
    TargetProc char(10) const options(*nopass);
  end-pi;

  dcl-s ProcName char(10);

  if %passed(TargetProc);
    ProcName = TargetProc;
  else;
    ProcName = 'DISPLAYPROC';  // Procedure that does exfmt
  endif;

  MsgCount += 1;
  snd-msg %trim(Msg) %target(ProcName);
end-proc;
```

**Display Procedure:**
```rpgle
dcl-proc ShowDetail;
  MsgRrn = 0;
  PGMQ = '*';
  MsgMore = *on;
  ClrPgmMsg('*' : 0 : '    ' : '*ALL' : MsgApiErr);

  dow *on;
    write MSGCTL;           // Write message control BEFORE exfmt
    exfmt DETAILSCR;        // Display format
    ClrPgmMsg('*' : 0 : '    ' : '*ALL' : MsgApiErr);  // Clear AFTER read

    if Validate();
      // Process valid data
    endif;
  enddo;
end-proc;
```

**Validation Procedure:**
```rpgle
dcl-proc Validate;
  MsgCount = 0;
  
  if Field1 = *blanks;
    SetError('Field 1 is required.');
  endif;
  
  return (MsgCount = 0);
end-proc;
```

### Key Rules

1. **SFLDSP/SFLDSPCTL must be unconditional** - No indicators
2. **Target the I/O procedure** - Messages go to procedure doing `exfmt`
3. **Use explicit procedure names** - Safer than offset calculations
4. **Write control BEFORE exfmt** - `write MSGCTL` then `exfmt DETAILSCR`
5. **Clear AFTER read** - `ClrPgmMsg` after user presses key
6. **Use %passed() for optional params** - Clearer than %parms()

---

## References

- **Working Example:** member:/R4SRCJHA/QRPGLESRC/ERMS950.SQLRPGLE
- **DDS Reference:** member:/R4SRCJHA/QDDSSRC/ERMS950FM.DSPF
- **IT Jungle Articles:** Message subfile implementation patterns (2012, 2022)
- **IBM Documentation:** SND-MSG with %TARGET parameter for procedure targeting

---

## Lessons Learned

1. **Message subfiles self-manage display** - They don't need indicator-driven SFLDSP when properly configured
2. **Procedure queues are isolated** - `snd-msg` without target goes to current procedure's private queue
3. **I/O procedure owns the queue** - Display file reads from the procedure executing `exfmt`
4. **Explicit is better than calculated** - Use procedure names rather than call-stack offset calculations
5. **Working examples are invaluable** - ERMS950 provided the pattern that solved the issue
