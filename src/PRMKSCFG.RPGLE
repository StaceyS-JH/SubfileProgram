**FREE
//==============================================================
// Program:     PRMKSCFG
// Description: Prompt to select KSFILE/KSLIB from KSCFG.
//              Returns blanks when user cancels.
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main)
        datfmt(*iso) timfmt(*hms)
        debug(*constants);

//--------------------------------------------------------------
// Display file
//--------------------------------------------------------------
dcl-f PRMKSCFG workstn indds(Ind) sfile(KCFGSFLD : SflRrn)
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
dcl-c KEY_F12       x'3C';

//--------------------------------------------------------------
// Indicator data structure
//--------------------------------------------------------------
dcl-ds Ind;
  SflClear    ind pos(90);
  SflEmpty    ind pos(91);
  SflMore     ind pos(93);
end-ds;

//--------------------------------------------------------------
// Subfile support
//--------------------------------------------------------------
dcl-s SflRrn uns(5) inz(0);

//--------------------------------------------------------------
// Forward prototypes
//--------------------------------------------------------------
dcl-pr LoadSubfile;
end-pr;

dcl-pr ProcessSelections;
  OutFile char(10);
  OutLib  char(10);
end-pr;

//--------------------------------------------------------------
// Main
//--------------------------------------------------------------
dcl-proc Main;

  dcl-pi Main;
    ParmFile char(10);
    ParmLib  char(10);
  end-pi;

  dcl-s Done     ind inz(*off);
  dcl-s SelFile  char(10) inz(*blanks);
  dcl-s SelLib   char(10) inz(*blanks);

  ParmFile = *blanks;
  ParmLib  = *blanks;

  LoadSubfile();

  dow not Done;
    write KCFGFOOT;
    exfmt KCFGCTL;

    select;
      when dspf_info.pressedKey = KEY_F3
        or dspf_info.pressedKey = KEY_F12;
        Done = *on;

      other;
        ProcessSelections(SelFile : SelLib);
        if SelFile <> *blanks and SelLib <> *blanks;
          ParmFile = SelFile;
          ParmLib  = SelLib;
          Done = *on;
        endif;
    endsl;
  enddo;

  *inlr = *on;

end-proc Main;

//--------------------------------------------------------------
// LoadSubfile
//--------------------------------------------------------------
dcl-proc LoadSubfile;

  dcl-s hFile     char(10);
  dcl-s hLib      char(10);
  dcl-s hActive   char(1);
  dcl-s hFunc     char(10);
  dcl-s LoadCount int(10) inz(0);

  SflClear = *on;
  SflMore  = *off;
  write KCFGCTL;
  SflClear = *off;
  SflRrn   = 0;

  exec sql
    declare C_KSCFG cursor for
      select KSFILE, KSLIB, ACTIVE, FUNCTION
        from KSCFG
       order by ACTIVE desc, FUNCTION, KSFILE, KSLIB;

  exec sql open C_KSCFG;
  if SQLSTATE <> '00000';
    KCFGCOUNT = 0;
    SflEmpty = *on;
    KERRMSG = 'Unable to load keystore configuration records.';
    write KCFGERR;
    write KCFGMPTY;
    return;
  endif;

  exec sql fetch C_KSCFG into :hFile, :hLib, :hActive, :hFunc;

  dow SQLSTATE = '00000';
    SFLOPT  = ' ';
    SFLFILE = hFile;
    SFLLIB  = hLib;
    SFLACT  = hActive;
    SFLFUNC = hFunc;
    SflRrn += 1;
    SFLRRN  = SflRrn;
    write KCFGSFLD;
    LoadCount += 1;

    exec sql fetch C_KSCFG into :hFile, :hLib, :hActive, :hFunc;
  enddo;

  exec sql close C_KSCFG;

  KCFGCOUNT = LoadCount;
  if LoadCount = 0;
    SflEmpty = *on;
    SflMore = *off;
    write KCFGMPTY;
  else;
    SflEmpty = *off;
    // SFLEND(*MORE): ON = Bottom, OFF = More...
    SflMore = (LoadCount <= 13);
  endif;

end-proc LoadSubfile;

//--------------------------------------------------------------
// ProcessSelections
//--------------------------------------------------------------
dcl-proc ProcessSelections;

  dcl-pi *n;
    OutFile char(10);
    OutLib  char(10);
  end-pi;

  dcl-s SelRrn uns(5);

  OutFile = *blanks;
  OutLib  = *blanks;

  if SflEmpty;
    return;
  endif;

  readc KCFGSFLD;
  if %eof(PRMKSCFG);
    KERRMSG = 'Type 1 and press Enter, or F3/F12 to exit.';
    write KCFGERR;
    return;
  endif;

  dow not %eof(PRMKSCFG);
    SelRrn = SFLRRN;

    if SFLOPT = '1';
      OutFile = SFLFILE;
      OutLib  = SFLLIB;
    endif;

    SFLOPT = ' ';
    SFLRRN = SelRrn;
    update KCFGSFLD;

    if OutFile <> *blanks and OutLib <> *blanks;
      return;
    endif;

    readc KCFGSFLD;
  enddo;

end-proc ProcessSelections;
