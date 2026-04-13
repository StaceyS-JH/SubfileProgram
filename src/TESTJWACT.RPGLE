**FREE
//==============================================================
// Program:     TESTJWACT
// Description: Simple test wrapper for GETJWACT.
//
// To run:
//   CALL PGM(MYLIB/TESTJWACT)
//
// Edit p_FunctionId below to a function that exists in
// JWTCFG_ACTIVE.
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main);

//--------------------------------------------------------------
// Prototype: GETJWACT
//--------------------------------------------------------------
dcl-pr GETJWACT extpgm('GETJWACT');
  FunctionId char(64);     // 1 input
  JwtLabel   char(36);     // 2 output
  Found      char(1);      // 3 output ('Y'/'N')
  ResultMsg  char(78);     // 4 output
end-pr;

//==============================================================
// Main
//==============================================================
dcl-proc Main;

  dcl-pi Main;
  end-pi;

  dcl-s p_FunctionId char(64) inz('DEFAULT_FUNCTION');
  dcl-s p_JwtLabel   char(36) inz(*blanks);
  dcl-s p_Found      char(1)  inz('N');
  dcl-s p_ResultMsg  char(78) inz(*blanks);

  dsply ('Lookup FUNCTION_ID: ' + %trimr(p_FunctionId));

  GETJWACT( p_FunctionId :
            p_JwtLabel   :
            p_Found      :
            p_ResultMsg  );

  dsply ('Found   : ' + p_Found);

  if p_Found = 'Y';
    dsply ('JWTLBL  : ' + %trimr(p_JwtLabel));
  else;
    dsply ('Message : ' + %trimr(p_ResultMsg));
  endif;

  *inlr = *on;

end-proc Main;
