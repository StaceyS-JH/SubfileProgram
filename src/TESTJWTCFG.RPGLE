**FREE
//==============================================================
// Program:     TESTJWTCFG
// Description: Test harness for JWTCFG table maintenance.
//              List screen loads rows from JWTCFG.
//              F6 opens a minimal Add panel and inserts a row.
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main)
  datfmt(*iso) timfmt(*hms);

//--------------------------------------------------------------
// Display file
//--------------------------------------------------------------
dcl-f TESTJWTCFG workstn indds(Ind) sfile(TJSFLD : SflRrn)
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
// Indicator data structure
//--------------------------------------------------------------
dcl-ds Ind;
  SflClear    ind pos(90);
  SflEmpty    ind pos(91);
  SflMore     ind pos(92);
end-ds;

//--------------------------------------------------------------
// Subfile RRN
//--------------------------------------------------------------
dcl-s SflRrn    uns(5)  inz(0);

//--------------------------------------------------------------
// State / working vars
//--------------------------------------------------------------
dcl-s Done      ind     inz(*off);
dcl-s LoadCount int(10) inz(0);

//--------------------------------------------------------------
// Forward prototypes
//--------------------------------------------------------------
dcl-pr LoadSubfile;
end-pr;

dcl-pr ShowAdd ind;
end-pr;

dcl-pr ClearDetail;
end-pr;

dcl-pr ValidateDetail ind;
end-pr;

dcl-pr InsertRow ind;
end-pr;

//--------------------------------------------------------------
// SQL options
//--------------------------------------------------------------
exec sql
  Set Option
    Commit    = *None,
    CloSqlCsr = *EndMod,
    DatFmt    = *ISO;

//==============================================================
// Main
//==============================================================
dcl-proc Main;

  write TJFOOT;
  LoadSubfile();

  dow not Done;
    write TJFOOT;
    exfmt TJCTL;

    select;
      when dspf_info.pressedKey = KEY_F3
        or dspf_info.pressedKey = KEY_F12;
        Done = *on;

      when dspf_info.pressedKey = KEY_F5;
        LoadSubfile();

      when dspf_info.pressedKey = KEY_F6;
        if ShowAdd();
          LoadSubfile();
        endif;

      other;
        // Plain Enter does a refresh for this test harness.
        LoadSubfile();
    endsl;
  enddo;

  *inlr = *on;

end-proc Main;

//==============================================================
// LoadSubfile
//==============================================================
dcl-proc LoadSubfile;

  dcl-pi *n;
  end-pi;

  dcl-s hJwtId   int(10);
  dcl-s hIssuer  varchar(128);
  dcl-s hSubject varchar(128);

  SflClear = *on;
  SflMore  = *on;
  write TJCTL;
  SflClear = *off;
  SflRrn   = 0;
  LoadCount = 0;

  exec sql
    DECLARE C_JWT CURSOR FOR
      SELECT JWTID, ISSUER, SUBJECT
        FROM JWTCFG
       ORDER BY ISSUER, SUBJECT;

  exec sql OPEN C_JWT;

  if SQLSTATE <> '00000';
    SflEmpty = *on;
    JWTCOUNT = 0;
    write TJMPTY;
    return;
  endif;

  exec sql FETCH C_JWT INTO :hJwtId, :hIssuer, :hSubject;

  dow SQLSTATE = '00000';
    SFLJWTID = hJwtId;
    SFLISS   = %subst(hIssuer  : 1 : %min(%len(hIssuer)  : 36));
    SFLSUB   = %subst(hSubject : 1 : %min(%len(hSubject) : 36));
    SflRrn  += 1;
    SFLRRN   = SflRrn;
    write TJSFLD;
    LoadCount += 1;

    exec sql FETCH C_JWT INTO :hJwtId, :hIssuer, :hSubject;
  enddo;

  exec sql CLOSE C_JWT;

  JWTCOUNT = LoadCount;
  SflMore = (LoadCount <= 13);

  if LoadCount = 0;
    SflEmpty = *on;
    write TJMPTY;
  else;
    SflEmpty = *off;
  endif;

end-proc LoadSubfile;

//==============================================================
// ShowAdd
//==============================================================
dcl-proc ShowAdd;

  dcl-pi *n ind;
  end-pi;

  dcl-s Saved ind inz(*off);

  ClearDetail();

  dow *on;
    exfmt TJDTL;

    if dspf_info.pressedKey = KEY_F12;
      leave;
    endif;

    if dspf_info.pressedKey = KEY_F10;
      if ValidateDetail();
        Saved = InsertRow();
        if Saved;
          leave;
        endif;
      endif;
    endif;
  enddo;

  return Saved;

end-proc ShowAdd;

//==============================================================
// ClearDetail
//==============================================================
dcl-proc ClearDetail;

  dcl-pi *n;
  end-pi;

  DISSUER   = '';
  DISUBJECT = '';
  DIAUDINC  = '';
  DIEXPIRY  = 900;
  DIKSFILE  = '';
  DIKSLIB   = '';
  DIKSLBL   = '';
  DIALG     = '';

end-proc ClearDetail;

//==============================================================
// ValidateDetail
//==============================================================
dcl-proc ValidateDetail;

  dcl-pi *n ind;
  end-pi;

  if %trimr(DISSUER) = '';
    return *off;
  endif;

  if %trimr(DISUBJECT) = '';
    return *off;
  endif;

  if %trimr(DIAUDINC) = '';
    return *off;
  endif;

  if DIEXPIRY <= 0;
    return *off;
  endif;

  if %trimr(DIKSFILE) = '';
    return *off;
  endif;

  if %trimr(DIKSLIB) = '';
    return *off;
  endif;

  if %trimr(DIKSLBL) = '';
    return *off;
  endif;

  if %trimr(DIALG) = '';
    return *off;
  endif;

  return *on;

end-proc ValidateDetail;

//==============================================================
// InsertRow
//==============================================================
dcl-proc InsertRow;

  dcl-pi *n ind;
  end-pi;

  dcl-s Iss varchar(128);
  dcl-s Sub varchar(128);
  dcl-s Aud varchar(256);
  dcl-s Ksf char(10);
  dcl-s Ksl char(10);
  dcl-s Kslbl char(32);
  dcl-s Alg char(10);

  Iss   = %trimr(DISSUER);
  Sub   = %trimr(DISUBJECT);
  Aud   = %trimr(DIAUDINC);
  Ksf   = DIKSFILE;
  Ksl   = DIKSLIB;
  Kslbl = DIKSLBL;
  Alg   = %upper(%trimr(DIALG));

  exec sql
    INSERT INTO JWTCFG
           (ISSUER, SUBJECT, AUDIENCE, EXPIRY_SEC,
            KSFILE, KSLIB, KSLABEL, JWALG,
            CREATETS, CHANGTS)
    VALUES (:Iss, :Sub, :Aud, :DIEXPIRY,
            :Ksf, :Ksl, :Kslbl, :Alg,
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

  if SQLSTATE = '00000' or SQLSTATE = '02000';
    return *on;
  endif;

  return *off;

end-proc InsertRow;
