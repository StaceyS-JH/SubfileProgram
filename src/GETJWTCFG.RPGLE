**FREE
//==============================================================
// Program:     GETJWTCFG
// Description: Standalone lookup program for JWTCFG by JWTLABEL.
//
// Call syntax:
//   CALL PGM(MYLIB/GETJWTCFG)
//        PARM( JwtLabel  KSFile  KSLib  KeyLabel  Algorithm
//              Issuer    Subject Audience ExpSecs
//              Found     ResultMsg )
//
// Parm  1 - JwtLabel   36A   INPUT
// Parm  2 - KSFile     10A   OUTPUT
// Parm  3 - KSLib      10A   OUTPUT
// Parm  4 - KeyLabel   32A   OUTPUT
// Parm  5 - Algorithm  10A   OUTPUT
// Parm  6 - Issuer    128A   OUTPUT
// Parm  7 - Subject   128A   OUTPUT
// Parm  8 - Audience  256A   OUTPUT
// Parm  9 - ExpSecs    10I   OUTPUT
// Parm 10 - Found       1A   OUTPUT ('Y' or 'N')
// Parm 11 - ResultMsg  78A   OUTPUT (blank on success)
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main)
  datfmt(*iso) timfmt(*hms);

exec sql
  Set Option
    Commit    = *None,
    CloSqlCsr = *EndMod,
    DatFmt    = *ISO;

//==============================================================
// Main
//==============================================================
dcl-proc Main;

  dcl-pi Main;
    ParmJwtLabel  char(36);
    ParmKSFile    char(10);
    ParmKSLib     char(10);
    ParmKeyLabel  char(32);
    ParmAlg       char(10);
    ParmIssuer    char(128);
    ParmSubject   char(128);
    ParmAudience  char(256);
    ParmExpSecs   int(10);
    ParmFound     char(1);
    ParmResultMsg char(78);
  end-pi;

  dcl-s InLabel varchar(36);

  // Initialize outputs
  ParmKSFile    = *blanks;
  ParmKSLib     = *blanks;
  ParmKeyLabel  = *blanks;
  ParmAlg       = *blanks;
  ParmIssuer    = *blanks;
  ParmSubject   = *blanks;
  ParmAudience  = *blanks;
  ParmExpSecs   = 0;
  ParmFound     = 'N';
  ParmResultMsg = *blanks;

  InLabel = %trimr(ParmJwtLabel);

  if InLabel = '';
    ParmResultMsg = 'JWT label is required.';
    *inlr = *on;
    return;
  endif;

  exec sql
    SELECT KSFILE,
           KSLIB,
           KSLABEL,
           JWALG,
           ISSUER,
           SUBJECT,
           AUDIENCE,
           EXPIRY_SEC
      INTO :ParmKSFile,
           :ParmKSLib,
           :ParmKeyLabel,
           :ParmAlg,
           :ParmIssuer,
           :ParmSubject,
           :ParmAudience,
           :ParmExpSecs
      FROM JWTCFG
     WHERE RTRIM(JWTLABEL) = RTRIM(:InLabel)
     ORDER BY CHANGTS DESC
     FETCH FIRST 1 ROW ONLY;

  if SQLSTATE = '00000';
    ParmFound = 'Y';
  elseif SQLSTATE = '02000';
    ParmResultMsg = 'No JWTCFG row found for JWTLABEL=' + %trimr(InLabel);
  else;
    ParmResultMsg = 'GETJWTCFG SQL error. SQLSTATE=' + SQLSTATE;
  endif;

  *inlr = *on;

end-proc Main;
