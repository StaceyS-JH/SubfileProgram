**FREE
//==============================================================
// Program:     KSCFGM
// Description: Keystore configuration maintenance for KSCFG.
//              Supports list, CRUD, activate, and work-with-keys.
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main)
        datfmt(*iso) timfmt(*hms)
        debug(*constants);

//--------------------------------------------------------------
// Display file
//--------------------------------------------------------------
dcl-f KSCFGD workstn indds(Ind) sfile(KSFSFLD : SflRrn)
                              sfile(KSFMSGSFL : MsgRrn)
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
dcl-c KEY_F5        x'35';
dcl-c KEY_F6        x'36';
dcl-c KEY_F10       x'3A';
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
  SflClear     ind pos(90);
  SflEmpty     ind pos(91);
  ViewMode     ind pos(92);
  SflMore      ind pos(93);   // *IN93 – SFLEND(*MORE) on list subfile
  MsgMore      ind pos(94);   // *IN94 – SFLEND(*MORE) on message subfile
end-ds;

//--------------------------------------------------------------
// Subfile/message support
//--------------------------------------------------------------
dcl-s SflRrn      uns(5)  inz(0);
dcl-s MsgRrn      uns(5)  inz(0);
dcl-s PGMQ        char(10) inz('*');
dcl-s MsgCount    int(10) inz(0);

//--------------------------------------------------------------
// Message queue API
//--------------------------------------------------------------
dcl-pr ClrPgmMsg extpgm('QMHRMVPM');
  StackEntry   char(10)  const;
  StackCount   int(10)   const;
  MsgKey       char(4)   const;
  MsgRemove    char(10)  const;
  ErrorCode    char(16)  options(*varsize);
end-pr;

dcl-s MsgApiErr char(16) inz(*allx'00');

//--------------------------------------------------------------
// Working row mirrors KSCFG
//--------------------------------------------------------------
dcl-ds WRow qualified;
  KscfgId  int(10)      inz(0);
  KsFile   char(10)     inz('');
  KsLib    char(10)     inz('');
  Active   char(1)      inz('N');
  Function char(10)     inz('NT-JWT');
  CreateTs varchar(26)  inz('');
  ChangTs  varchar(26)  inz('');
end-ds;

//--------------------------------------------------------------
// External program prototypes
//--------------------------------------------------------------
dcl-pr CRTKSD extpgm('CRTKSD');
  CreatedFile  char(10);
  CreatedLib   char(10);
  CreatedFunc  char(10);
  WriteToCfg   char(1);
end-pr;

dcl-pr LSTKSRCD extpgm('LSTKSRCD');
  p_File char(10);
  p_Lib  char(10);
end-pr;

//--------------------------------------------------------------
// Forward prototypes
//--------------------------------------------------------------
dcl-pr LoadSubfile;
end-pr;

dcl-pr ProcessSelections;
end-pr;

dcl-pr FetchRow;
  SelId int(10) const;
end-pr;

dcl-pr ShowDetail ind;
  Mode char(1) const; // C=change V=view
end-pr;

dcl-pr ConfirmDelete ind;
end-pr;

dcl-pr DoUpdate ind;
end-pr;

dcl-pr DoDelete ind;
end-pr;

dcl-pr MakeActive;
  SelId int(10) const;
end-pr;

dcl-pr LaunchCreate;
end-pr;

dcl-pr CallWorkKeys;
  File char(10) const;
  Lib  char(10) const;
end-pr;

dcl-pr RowToDetail;
end-pr;

dcl-pr DetailToRow;
end-pr;

dcl-pr ValidateDetail ind;
end-pr;

dcl-pr ResetErrorAttrs;
end-pr;

dcl-pr SetError;
  Msg varchar(78) const;
  TargetProc char(10) const options(*nopass);
end-pr;

exec sql
  Set Option
    Commit    = *None,
    CloSqlCsr = *EndMod,
    DatFmt    = *ISO;

//==============================================================
// Main
//==============================================================
dcl-proc Main;

  dcl-s Done ind inz(*off);

  write KSFFOOT;
  LoadSubfile();

  dow not Done;
    write KSFFOOT;
    exfmt KSFCTL;

    select;
      when dspf_info.pressedKey = KEY_F3
        or dspf_info.pressedKey = KEY_F12;
        Done = *on;

      when dspf_info.pressedKey = KEY_F5;
        LoadSubfile();

      when dspf_info.pressedKey = KEY_F6;
        LaunchCreate();
        LoadSubfile();

      other;
        ProcessSelections();
    endsl;
  enddo;

  *inlr = *on;

end-proc Main;

//==============================================================
// LoadSubfile
//==============================================================
dcl-proc LoadSubfile;

  dcl-s hId       int(10);
  dcl-s hFile     char(10);
  dcl-s hLib      char(10);
  dcl-s hActive   char(1);
  dcl-s hFunc     char(10);
  dcl-s LoadCount int(10) inz(0);

  SflClear = *on;
  // SFLEND(*MORE): ON = Bottom, OFF = More...
  SflMore = *on;
  write KSFCTL;
  SflClear = *off;
  SflRrn = 0;

  exec sql
    declare C_KSCFG cursor for
      select KSCFGID, KSFILE, KSLIB, ACTIVE, FUNCTION
        from KSCFG
       order by ACTIVE desc, FUNCTION, KSFILE, KSLIB;

  exec sql open C_KSCFG;
  if SQLSTATE <> '00000';
    SetError('Cannot open KSCFG cursor: ' + SQLSTATE);
    SflEmpty = *on;
    write KSFMPTY;
    return;
  endif;

  exec sql fetch C_KSCFG into :hId, :hFile, :hLib, :hActive, :hFunc;

  dow SQLSTATE = '00000';
    SFLID   = hId;
    SFLOPT  = ' ';
    SFLFILE = hFile;
    SFLLIB  = hLib;
    SFLACT  = hActive;
    SFLFUNC = hFunc;
    SflRrn += 1;
    SFLRRN  = SflRrn;
    write KSFSFLD;
    LoadCount += 1;

    exec sql fetch C_KSCFG into :hId, :hFile, :hLib, :hActive, :hFunc;
  enddo;

  exec sql close C_KSCFG;

  KSFCOUNT = LoadCount;
  if LoadCount = 0;
    SflEmpty = *on;
    SflMore = *on;
    write KSFMPTY;
  else;
    SflEmpty = *off;
    SflMore = (LoadCount <= 13);
  endif;

end-proc LoadSubfile;

//==============================================================
// ProcessSelections
//==============================================================
dcl-proc ProcessSelections;

  dcl-s SelRrn uns(5);
  dcl-s SelId  int(10);
  dcl-s SelOpt char(1);

  readc KSFSFLD;
  if %eof(KSCFGD);
    LoadSubfile();
    return;
  endif;

  dow not %eof(KSCFGD);
    SelRrn = SFLRRN;
    SelId  = SFLID;
    SelOpt = %upper(SFLOPT);

    SFLOPT = ' ';
    SFLRRN = SelRrn;
    update KSFSFLD;

    select;
      when SelOpt = '2';
        FetchRow(SelId);
        if WRow.KscfgId > 0;
          if ShowDetail('C');
            LoadSubfile();
          endif;
        endif;

      when SelOpt = '4';
        FetchRow(SelId);
        if WRow.KscfgId > 0;
          if ConfirmDelete();
            LoadSubfile();
          endif;
        endif;

      when SelOpt = '5';
        FetchRow(SelId);
        if WRow.KscfgId > 0;
          ShowDetail('V');
        endif;

      when SelOpt = 'A';
        MakeActive(SelId);
        LoadSubfile();

      when SelOpt = '9';
        FetchRow(SelId);
        if WRow.KscfgId > 0;
          CallWorkKeys(%trimr(WRow.KsFile) : %trimr(WRow.KsLib));
          write KSFFOOT;
        endif;

      other;
        SetError('Valid options: 2,4,5,A,9.');
    endsl;

    readc KSFSFLD;
  enddo;

end-proc ProcessSelections;

//==============================================================
// FetchRow
//==============================================================
dcl-proc FetchRow;

  dcl-pi *n;
    SelId int(10) const;
  end-pi;

  WRow.KscfgId = 0;

  exec sql
    select KSCFGID, KSFILE, KSLIB, ACTIVE, FUNCTION,
           char(CREATETS), char(CHANGTS)
      into :WRow.KscfgId, :WRow.KsFile, :WRow.KsLib,
           :WRow.Active, :WRow.Function,
           :WRow.CreateTs, :WRow.ChangTs
      from KSCFG
     where KSCFGID = :SelId;

  if SQLSTATE <> '00000';
    SetError('KSCFG row not found: ' + SQLSTATE);
    WRow.KscfgId = 0;
  endif;

end-proc FetchRow;

//==============================================================
// ShowDetail
//==============================================================
dcl-proc ShowDetail;

  dcl-pi *n ind;
    Mode char(1) const;
  end-pi;

  dcl-s Saved ind inz(*off);

  ViewMode = (Mode = 'V');
  if Mode = 'C';
    DTLMODE = 'Change';
  else;
    DTLMODE = 'View  ';
  endif;

  RowToDetail();
  ResetErrorAttrs();
  MsgRrn = 0;
  PGMQ = 'KSCFGM';
  MsgMore = *on;
  ClrPgmMsg(PGMQ : 0 : '    ' : '*ALL      ' : MsgApiErr);

  dow *on;
    write KSFMSGCTL;
    exfmt KSFDTL;
    ClrPgmMsg(PGMQ : 0 : '    ' : '*ALL      ' : MsgApiErr);

    if dspf_info.pressedKey = KEY_F12;
      leave;
    endif;

    if Mode = 'V';
      leave;
    endif;

    if dspf_info.pressedKey = KEY_F10;
      MsgCount = 0;
      MsgMore = *on;

      if not ValidateDetail();
        MsgMore = (MsgCount <= 1);
        iter;
      endif;

      DetailToRow();
      Saved = DoUpdate();
      if Saved;
        leave;
      endif;
    endif;
  enddo;

  // Clear detail-message overlay remnants and restore list footer.
  MsgRrn = 0;
  MsgMore = *on;
  write KSFMSGCTL;
  write KSFFOOT;

  return Saved;

end-proc ShowDetail;

//==============================================================
// ConfirmDelete
//==============================================================
dcl-proc ConfirmDelete;

  dcl-pi *n ind;
  end-pi;

  DELID   = WRow.KscfgId;
  DELFILE = WRow.KsFile;
  DELLIB  = WRow.KsLib;
  DELFUNC = WRow.Function;

  exfmt KSFDEL;
  if dspf_info.pressedKey = KEY_F10;
    return DoDelete();
  endif;

  return *off;

end-proc ConfirmDelete;

//==============================================================
// DoUpdate
//==============================================================
dcl-proc DoUpdate;

  dcl-pi *n ind;
  end-pi;

  exec sql
    update KSCFG
       set KSFILE   = :WRow.KsFile,
           KSLIB    = :WRow.KsLib,
           ACTIVE   = :WRow.Active,
           FUNCTION = :WRow.Function,
           CHANGTS  = current_timestamp
     where KSCFGID  = :WRow.KscfgId;

  if SQLSTATE = '00000';
    return *on;
  endif;

  SetError('Update failed: ' + SQLSTATE);
  return *off;

end-proc DoUpdate;

//==============================================================
// DoDelete
//==============================================================
dcl-proc DoDelete;

  dcl-pi *n ind;
  end-pi;

  exec sql
    delete from KSCFG
     where KSCFGID = :WRow.KscfgId;

  if SQLSTATE = '00000';
    return *on;
  endif;

  SetError('Delete failed: ' + SQLSTATE);
  return *off;

end-proc DoDelete;

//==============================================================
// MakeActive
//==============================================================
dcl-proc MakeActive;

  dcl-pi *n;
    SelId int(10) const;
  end-pi;

  exec sql
    update KSCFG
       set ACTIVE = 'N',
           CHANGTS = current_timestamp
     where ACTIVE = 'Y';

  exec sql
    update KSCFG
       set ACTIVE = 'Y',
           CHANGTS = current_timestamp
     where KSCFGID = :SelId;

  if SQLSTATE <> '00000';
    SetError('Activate failed: ' + SQLSTATE);
  endif;

end-proc MakeActive;

//==============================================================
// LaunchCreate (calls CRTKSD)
//==============================================================
dcl-proc LaunchCreate;

  dcl-s NewFile char(10) inz(*blanks);
  dcl-s NewLib  char(10) inz(*blanks);
  dcl-s NewFunc char(10) inz(*blanks);
  dcl-s WriteCfg char(1) inz('N');

  CRTKSD(NewFile : NewLib : NewFunc : WriteCfg);

  if %trimr(NewFile) = *blanks or %trimr(NewLib) = *blanks;
    return;
  endif;

  if %upper(%trimr(WriteCfg)) = 'Y';
    SetError('Keystore created; CRTKSD handled KSCFG registration.');
  else;
    SetError('Keystore created; not written to KSCFG (Write flag <> Y).');
  endif;

end-proc LaunchCreate;

//==============================================================
// CallWorkKeys
//==============================================================
dcl-proc CallWorkKeys;

  dcl-pi *n;
    File char(10) const;
    Lib  char(10) const;
  end-pi;

  dcl-s wFile char(10);
  dcl-s wLib  char(10);

  wFile = File;
  wLib  = Lib;
  LSTKSRCD(wFile : wLib);

end-proc CallWorkKeys;

//==============================================================
// RowToDetail
//==============================================================
dcl-proc RowToDetail;

  DKSID   = WRow.KscfgId;
  DKSFILE = WRow.KsFile;
  DKSLIB  = WRow.KsLib;
  DKSACT  = WRow.Active;
  DKSFUNC = WRow.Function;
  DKSCRTS = WRow.CreateTs;
  DKSCHTS = WRow.ChangTs;

end-proc RowToDetail;

//==============================================================
// DetailToRow
//==============================================================
dcl-proc DetailToRow;

  WRow.KsFile   = DKSFILE;
  WRow.KsLib    = DKSLIB;
  WRow.Active   = %upper(%trimr(DKSACT));
  WRow.Function = %upper(%trimr(DKSFUNC));

end-proc DetailToRow;

//==============================================================
// SetError
//==============================================================
//==============================================================
// Procedure: SetError
// Sends an error message to the program message queue.
// Parameters:
//   Msg        - Error message text (max 78 chars)
//   TargetProc - Optional procedure name that does the exfmt
//                (defaults to 'SHOWDETAIL' for KSCFGM)
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

  // Default to ShowDetail if not specified
  if %passed(TargetProc);
    ProcName = TargetProc;
  else;
    ProcName = 'SHOWDETAIL';
  endif;

  MsgCount += 1;
  snd-msg %trim(Msg) %target(ProcName);

end-proc SetError;

//==============================================================
// ValidateDetail
//==============================================================
dcl-proc ValidateDetail;

  dcl-pi *n ind;
  end-pi;

  dcl-s Valid ind inz(*on);

  ResetErrorAttrs();

  if %trimr(DKSFILE) = *blanks;
    ATTRFILE = ATTR_RED_RI;
    SetError('KS File is required.');
    if Valid;
      CSRROW = 6;
      CSRCOL = 12;
    endif;
    Valid = *off;
  endif;

  if %trimr(DKSLIB) = *blanks;
    ATTRLIB = ATTR_RED_RI;
    SetError('Library is required.');
    if Valid;
      CSRROW = 7;
      CSRCOL = 12;
    endif;
    Valid = *off;
  endif;

  if %trimr(DKSACT) <> 'Y' and %trimr(DKSACT) <> 'N';
    ATTRACT = ATTR_RED_RI;
    SetError('Active must be Y or N.');
    if Valid;
      CSRROW = 8;
      CSRCOL = 15;
    endif;
    Valid = *off;
  endif;

  return Valid;

end-proc ValidateDetail;

//==============================================================
// ResetErrorAttrs
//==============================================================
dcl-proc ResetErrorAttrs;

  ATTRFILE = ATTR_GRN_UL;
  ATTRLIB  = ATTR_GRN_UL;
  ATTRACT  = ATTR_GRN_UL;
  ATTRFUNC = ATTR_GRN_UL;

end-proc ResetErrorAttrs;
