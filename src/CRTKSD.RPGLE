**FREE
// Program:     CRTKSD
// Description: Screen driver for CRTKS. Collects keystore
//              creation parameters, validates input, shows
//              message-subfile diagnostics, and calls CRTKS.
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main)
        debug(*constants);

exec sql
  Set Option
    Commit    = *None,
    CloSqlCsr = *EndMod,
    DatFmt    = *ISO;

//--------------------------------------------------------------
// Display file
//--------------------------------------------------------------
dcl-f CRTKSD workstn indds(Ind) sfile(CRTMSGSFL : MsgRrn)
                              infds(dspf_info);

//--------------------------------------------------------------
// Workstation INFDS (key capture)
//--------------------------------------------------------------
dcl-ds dspf_info qualified;
  pressedKey char(1) pos(369);
end-ds;

//--------------------------------------------------------------
// 5250 key constants
//--------------------------------------------------------------
dcl-c KEY_F3        x'33';
dcl-c KEY_F6        x'36';
dcl-c KEY_F12       x'3C';

//--------------------------------------------------------------
// Display attribute constants
//--------------------------------------------------------------
dcl-c ATTR_GRN_UL   x'24';
dcl-c ATTR_RED_RI   x'29';

//--------------------------------------------------------------
// Indicator data structure
//--------------------------------------------------------------
dcl-ds Ind;
  MsgMore    ind pos(94);   // *IN94 – SFLEND(*MORE) on message subfile
end-ds;

//--------------------------------------------------------------
// Message subfile support
//--------------------------------------------------------------
dcl-s MsgRrn      uns(5)  inz(0);
dcl-s PGMQ        char(10) inz('*');
dcl-s MsgCount    int(10) inz(0);

dcl-pr ClrPgmMsg extpgm('QMHRMVPM');
  StackEntry   char(10)  const;
  StackCount   int(10)   const;
  MsgKey       char(4)   const;
  MsgRemove    char(10)  const;
  ErrorCode    char(16)  options(*varsize);
end-pr;

dcl-s MsgApiErr char(16) inz(*allx'00');

//--------------------------------------------------------------
// Prototype: CRTKS external program
//--------------------------------------------------------------
dcl-pr CRTKS extpgm('CRTKS');
  ck_File       char(10);
  ck_Lib        char(10);
  ck_MasterKey  int(10);
  ck_Desc       char(50);
  ck_Auth       char(10);
end-pr;

//--------------------------------------------------------------
// Forward prototypes
//--------------------------------------------------------------
dcl-pr ResetErrorAttrs;
end-pr;

dcl-pr SetError;
  Msg varchar(78) const;
  TargetProc char(10) const options(*nopass);
end-pr;

dcl-pr ValidateInput ind;
end-pr;

dcl-pr RegisterInKscfg;
  RegFile   char(10) const;
  RegLib    char(10) const;
  RegFunc   char(10) const;
  StatusMsg varchar(78);
end-pr;

//==============================================================
// Main procedure
//==============================================================
dcl-proc Main;

  dcl-pi Main;
    CreatedFile  char(10)  options(*nopass);   // OUTPUT: file name on success
    CreatedLib   char(10)  options(*nopass);   // OUTPUT: library on success
    CreatedFunc  char(10)  options(*nopass);   // OUTPUT: function on success
    WriteToCfg   char(1)   options(*nopass);   // OUTPUT: Y/N write flag
  end-pi;

  dcl-s Done      ind inz(*off);
  dcl-s Created   ind inz(*off);
  dcl-s WkFile    char(10);
  dcl-s WkLib     char(10);
  dcl-s WkDesc    char(50);
  dcl-s WkAuth    char(10);
  dcl-s WkMKey    int(10);
  dcl-s WkFunc    char(10);
  dcl-s WkWrite   char(1);
  dcl-s RegMsg    varchar(78);

  // Initialize screen fields with defaults
  CKSFILE   = *blanks;
  CKSLIB    = *blanks;
  CKSDESC   = *blanks;
  CKSAUTH   = '*EXCLUDE  ';
  CKSMKEY   = 4;
  CKSFUNC   = *blanks;
  CKSWCFG   = 'N';
  MsgRrn    = 0;
  MsgMore   = *on;
  PGMQ      = '*';
  ResetErrorAttrs();

  dow not Done and not Created;

    write CRTMSGCTL;
    exfmt CRTKSSCR;
    ClrPgmMsg('*' : 0 : '    ' : '*ALL      ' : MsgApiErr);

    select;

      // F3 / F12 – Exit without creating
      when dspf_info.pressedKey = KEY_F3
        or dspf_info.pressedKey = KEY_F12;
        Done = *on;

      // F6 – Validate and create
      when dspf_info.pressedKey = KEY_F6;

        MsgCount = 0;
        MsgMore = *on;

        if not ValidateInput();
          MsgMore = (MsgCount <= 1);
          iter;
        endif;

        WkFile  = CKSFILE;
        WkLib   = CKSLIB;
        WkDesc  = CKSDESC;
        WkMKey  = CKSMKEY;
        WkFunc  = %upper(%trimr(CKSFUNC));
        WkWrite = %upper(%trimr(CKSWCFG));
        if WkWrite = *blanks;
          WkWrite = 'N';
        endif;

        if %trimr(CKSAUTH) = *blanks;
          WkAuth = '*EXCLUDE  ';
        else;
          WkAuth = CKSAUTH;
        endif;

        CRTKS(WkFile : WkLib : WkMKey : WkDesc : WkAuth);

        SetError('Keystore ' + %trimr(WkFile) + '/'
               + %trimr(WkLib) + ' created successfully.');

        if WkWrite = 'Y';
          RegisterInKscfg(WkFile : WkLib : WkFunc : RegMsg);
          if %trim(RegMsg) <> '';
            SetError(RegMsg);
          endif;
        endif;

        if %passed(CreatedFile);
          CreatedFile = WkFile;
        endif;
        if %passed(CreatedLib);
          CreatedLib = WkLib;
        endif;
        if %passed(CreatedFunc);
          CreatedFunc = WkFunc;
        endif;
        if %passed(WriteToCfg);
          WriteToCfg = WkWrite;
        endif;

        Created = *on;

      other;
        SetError('Use F6=Create, F3=Exit, or F12=Previous.');

    endsl;

  enddo;

  // If created, pause so user can read the success message.
  if Created;
    MsgRrn = 0;
    MsgMore = *on;
    write CRTMSGCTL;
    exfmt CRTKSSCR;
    ClrPgmMsg('*' : 0 : '    ' : '*ALL      ' : MsgApiErr);
  endif;

  *inlr = *on;

end-proc Main;

//==============================================================
// Procedure: SetError
// Sends a message to the program message queue.
//==============================================================
//==============================================================
// Procedure: SetError
// Sends an error message to the program message queue.
// Parameters:
//   Msg        - Error message text (max 78 chars)
//   TargetProc - Optional procedure name that does the exfmt
//                (defaults to 'MAIN' for CRTKSD)
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

  // Default to Main if not specified
  if %passed(TargetProc);
    ProcName = TargetProc;
  else;
    ProcName = 'MAIN';
  endif;

  MsgCount += 1;
  snd-msg %trim(Msg) %target(ProcName);

end-proc SetError;

//==============================================================
// Procedure: ValidateInput
// Validates screen input and marks invalid fields.
//==============================================================
dcl-proc ValidateInput;

  dcl-pi *n ind;
  end-pi;

  dcl-s Valid ind inz(*on);
  dcl-s AuthIn char(10);

  ResetErrorAttrs();

  if %trimr(CKSFILE) = *blanks;
    ATTRFILE = ATTR_RED_RI;
    SetError('Keystore file name is required.');
    if Valid;
      CSRROW = 6;
      CSRCOL = 12;
    endif;
    Valid = *off;
  endif;

  if %trimr(CKSLIB) = *blanks;
    ATTRLIB = ATTR_RED_RI;
    SetError('Library is required.');
    if Valid;
      CSRROW = 6;
      CSRCOL = 34;
    endif;
    Valid = *off;
  endif;

  if CKSMKEY < 1 or CKSMKEY > 8;
    ATTRMKEY = ATTR_RED_RI;
    SetError('Master Key ID must be 1 through 8.');
    if Valid;
      CSRROW = 12;
      CSRCOL = 17;
    endif;
    Valid = *off;
  endif;

  if %upper(%trimr(CKSWCFG)) <> *blanks
    and %upper(%trimr(CKSWCFG)) <> 'Y'
    and %upper(%trimr(CKSWCFG)) <> 'N';
    ATTRWCFG = ATTR_RED_RI;
    SetError('Write to KeyStore Config File must be Y or N.');
    if Valid;
      CSRROW = 15;
      CSRCOL = 34;
    endif;
    Valid = *off;
  endif;

  AuthIn = %upper(%trimr(CKSAUTH));
  if AuthIn <> *blanks
    and AuthIn <> '*EXCLUDE'
    and AuthIn <> '*USE'
    and AuthIn <> '*CHANGE'
    and AuthIn <> '*ALL';
    ATTRAUTH = ATTR_RED_RI;
    SetError('Authority must be *EXCLUDE, *USE, *CHANGE, or *ALL.');
    if Valid;
      CSRROW = 10;
      CSRCOL = 13;
    endif;
    Valid = *off;
  endif;

  return Valid;

end-proc ValidateInput;

//==============================================================
// Procedure: ResetErrorAttrs
// Clears all P-field attributes to default green underline.
//==============================================================
dcl-proc ResetErrorAttrs;

  dcl-pi *n;
  end-pi;

  ATTRFILE = ATTR_GRN_UL;
  ATTRLIB  = ATTR_GRN_UL;
  ATTRDESC = ATTR_GRN_UL;
  ATTRAUTH = ATTR_GRN_UL;
  ATTRMKEY = ATTR_GRN_UL;
  ATTRFUNC = ATTR_GRN_UL;
  ATTRWCFG = ATTR_GRN_UL;

end-proc ResetErrorAttrs;

//==============================================================
// Procedure: RegisterInKscfg
// Registers the created keystore in KSCFG when requested.
//==============================================================
dcl-proc RegisterInKscfg;

  dcl-pi *n;
    RegFile   char(10) const;
    RegLib    char(10) const;
    RegFunc   char(10) const;
    StatusMsg varchar(78);
  end-pi;

  dcl-s ExistingCnt int(10) inz(0);
  dcl-s ActiveCnt   int(10) inz(0);
  dcl-s NewActive   char(1) inz('N');

  StatusMsg = '';

  exec sql
    select count(*)
      into :ExistingCnt
      from KSCFG
     where KSFILE = :RegFile
       and KSLIB  = :RegLib;

  if ExistingCnt > 0;
    StatusMsg = 'KSCFG already has ' + %trimr(RegFile)
              + '/' + %trimr(RegLib) + '.';
    return;
  endif;

  exec sql
    select count(*)
      into :ActiveCnt
      from KSCFG
     where ACTIVE = 'Y';

  if ActiveCnt = 0;
    NewActive = 'Y';
  endif;

  exec sql
    insert into KSCFG
      (KSFILE, KSLIB, ACTIVE, FUNCTION, CHANGTS)
    values
      (:RegFile, :RegLib, :NewActive, :RegFunc, current_timestamp);

  if SQLSTATE = '00000' or SQLSTATE = '02000';
    StatusMsg = 'KSCFG registration completed for '
              + %trimr(RegFile) + '/' + %trimr(RegLib) + '.';
  else;
    StatusMsg = 'Create succeeded; KSCFG insert failed: ' + SQLSTATE;
  endif;

end-proc RegisterInKscfg;
