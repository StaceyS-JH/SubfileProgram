**FREE
//==============================================================
// Program:     TESTGETCFG
// Description: Simple test wrapper for GETJWTCFG.
//
// To run:
//   CALL PGM(MYLIB/TESTGETCFG)
//
// Edit p_JwtLabel below to a label that exists in JWTCFG.JWTLABEL.
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main);

//--------------------------------------------------------------
// Prototype: GETJWTCFG
//--------------------------------------------------------------
dcl-pr GETJWTCFG extpgm('GETJWTCFG');
  JwtLabel   char(36);     //  1 input
  KSFile     char(10);     //  2 output
  KSLib      char(10);     //  3 output
  KeyLabel   char(32);     //  4 output
  Algorithm  char(10);     //  5 output
  Issuer     char(128);    //  6 output
  Subject    char(128);    //  7 output
  Audience   char(256);    //  8 output
  ExpSecs    int(10);      //  9 output
  Found      char(1);      // 10 output ('Y'/'N')
  ResultMsg  char(78);     // 11 output
end-pr;

//==============================================================
// Main
//==============================================================
dcl-proc Main;

  dcl-pi Main;
  end-pi;

  dcl-s p_JwtLabel  char(36)  inz('DEFAULT-JWT-CFG');
  dcl-s p_KSFile    char(10)  inz(*blanks);
  dcl-s p_KSLib     char(10)  inz(*blanks);
  dcl-s p_KeyLabel  char(32)  inz(*blanks);
  dcl-s p_Algorithm char(10)  inz(*blanks);
  dcl-s p_Issuer    char(128) inz(*blanks);
  dcl-s p_Subject   char(128) inz(*blanks);
  dcl-s p_Audience  char(256) inz(*blanks);
  dcl-s p_ExpSecs   int(10)   inz(0);
  dcl-s p_Found     char(1)   inz('N');
  dcl-s p_ResultMsg char(78)  inz(*blanks);

  dsply ('Lookup JWTLABEL: ' + %trimr(p_JwtLabel));

  GETJWTCFG( p_JwtLabel  :
             p_KSFile    :
             p_KSLib     :
             p_KeyLabel  :
             p_Algorithm :
             p_Issuer    :
             p_Subject   :
             p_Audience  :
             p_ExpSecs   :
             p_Found     :
             p_ResultMsg );

  dsply ('Found   : ' + p_Found);

  if p_Found = 'Y';
    dsply ('KSFile  : ' + %trimr(p_KSFile));
    dsply ('KSLib   : ' + %trimr(p_KSLib));
    dsply ('KeyLbl  : ' + %trimr(p_KeyLabel));
    dsply ('Alg     : ' + %trimr(p_Algorithm));
    dsply ('Issuer  : ' + %subst(%trimr(p_Issuer)  : 1 : %min(52 : %len(%trimr(p_Issuer)))));
    dsply ('Subject : ' + %subst(%trimr(p_Subject) : 1 : %min(52 : %len(%trimr(p_Subject)))));
    dsply ('Audience: ' + %subst(%trimr(p_Audience): 1 : %min(52 : %len(%trimr(p_Audience)))));
    dsply ('ExpSecs : ' + %char(p_ExpSecs));
  else;
    dsply ('Message : ' + %trimr(p_ResultMsg));
  endif;

  *inlr = *on;

end-proc Main;
