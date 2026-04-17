**FREE
//==============================================================
// Program:     TESTACCTKN
// Description: Test wrapper for GETACCTKN. Sets sample inputs,
//              calls GETACCTKN, and displays success/error values.
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main)
        option(*srcstmt : *nodebugio);

//--------------------------------------------------------------
// Prototype: GETACCTKN
//--------------------------------------------------------------
dcl-pr GETACCTKN extpgm('GETACCTKN');
  JwtLabel     char(36);
  AccessToken  char(4096);
  ExpiresIn    int(10);
  ErrorMsg     char(256);
  HttpRc       int(10);
  Scope        char(512) options(*nopass);
end-pr;

//==============================================================
// Main
//==============================================================
dcl-proc Main;

  dcl-pi Main;
    p_Environment char(3);
  end-pi;

  dcl-s wJwtLabel    char(36)   inz(*blanks);

  dcl-s wAccessToken char(4096) inz(*blanks);
  dcl-s wExpiresIn   int(10)    inz(0);
  dcl-s wErrorMsg    char(256)  inz(*blanks);
  dcl-s wHttpRc      int(10)    inz(0);
  dcl-s wScope       char(512)  inz(*blanks);

  if %trimr(p_Environment) = '';
    p_Environment = 'DEV';
  endif;

  // Sample environment values. Adjust as needed for your tenant.
  select;
    when %upper(%trimr(p_Environment)) = 'STG';
      wJwtLabel = 'BSL-STG';
      wScope = 'openid profile';

    other;
      wJwtLabel = 'BSL-DEV';
      wScope = 'openid email';
  endsl;

  dsply ('Env      : ' + %trimr(p_Environment));
  dsply ('JWTLabel : ' + %trimr(wJwtLabel));
  dsply ('Scope    : ' + %trimr(wScope));

  callp GETACCTKN(
      wJwtLabel
    : wAccessToken
    : wExpiresIn
    : wErrorMsg
    : wHttpRc
    : wScope);

  if %trimr(wErrorMsg) <> '';
    dsply ('HTTP rc  : ' + %char(wHttpRc));
    dsply ('Error    : ' + %trimr(wErrorMsg));
  else;
    dsply ('HTTP rc  : ' + %char(wHttpRc));
    dsply ('Expires  : ' + %char(wExpiresIn));
    dsply ('Token(1) : ' + %subst(wAccessToken : 1 : 50));
    dsply ('Token(2) : ' + %subst(wAccessToken : 51 : 50));
  endif;

  *inlr = *on;

end-proc;
