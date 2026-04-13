**FREE
//==============================================================
// Program:     GETJWACT
// Description: Resolves the active JWTLABEL for a given FUNCTION_ID
//              from JWTCFG_ACTIVE.
//
// Call syntax:
//   CALL PGM(MYLIB/GETJWACT)
//        PARM( FunctionId  JwtLabel  Found  ResultMsg )
//
// Parm 1 - FunctionId  64A   INPUT
// Parm 2 - JwtLabel    36A   OUTPUT
// Parm 3 - Found        1A   OUTPUT ('Y' or 'N')
// Parm 4 - ResultMsg   78A   OUTPUT (blank on success)
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
    ParmFunctionId char(64);
    ParmJwtLabel   char(36);
    ParmFound      char(1);
    ParmResultMsg  char(78);
  end-pi;

  dcl-s InFunctionId varchar(64);

  // Initialize outputs
  ParmJwtLabel  = *blanks;
  ParmFound     = 'N';
  ParmResultMsg = *blanks;

  InFunctionId = %trimr(ParmFunctionId);

  if InFunctionId = '';
    ParmResultMsg = 'Function ID is required.';
    *inlr = *on;
    return;
  endif;

  exec sql
    SELECT JWTLABEL
      INTO :ParmJwtLabel
      FROM JWTCFG_ACTIVE
     WHERE RTRIM(FUNCTION_ID) = RTRIM(:InFunctionId)
       AND ACTIVE = 'Y'
     FETCH FIRST 1 ROW ONLY;

  if SQLSTATE = '00000';
    ParmFound = 'Y';
  elseif SQLSTATE = '02000';
    ParmResultMsg = 'No active JWT label found for FUNCTION_ID=' +
                    %trimr(InFunctionId);
  else;
    ParmResultMsg = 'GETJWACT SQL error. SQLSTATE=' + SQLSTATE;
  endif;

  *inlr = *on;

end-proc Main;
