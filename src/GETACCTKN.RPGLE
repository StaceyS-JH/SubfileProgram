**FREE
//==============================================================
// Program:     GETACCTKN
// Description: Builds a client assertion JWT (via JWTGEN), posts
//              an OAuth client_credentials request, and returns
//              access token metadata to the caller.
//
// External parms are fixed CHAR/INT to keep CL and RPG callers
// compatible. Internally we trim and validate before use.
//
// Call syntax:
//   CALL PGM(MYLIB/GETACCTKN)
//        PARM( JwtLabel  AccessToken  ExpiresIn  ErrorMsg  HttpRc )
//
// Parm  1 - JwtLabel      36A   INPUT
// Parm  2 - AccessToken 4096A   OUTPUT
// Parm  3 - ExpiresIn     10I   OUTPUT
// Parm  4 - ErrorMsg     256A   OUTPUT (blank on success)
// Parm  5 - HttpRc        10I   OUTPUT (HTTPAPI transport rc)
//
// Notes:
// - JWT signing config is loaded by JwtLabel via GETJWTCFG.
// - Audience is used as the token endpoint URL.
// - Scope defaults to 'openid'.
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*new) main(Main)
        datfmt(*iso)
        option(*srcstmt : *nodebugio);

/include qcpysrc,httpapi_h

//--------------------------------------------------------------
// External program prototypes
//--------------------------------------------------------------
dcl-pr JWTGEN extpgm('JWTGEN');
  KSFile     char(10);
  KSLib      char(10);
  KeyLabel   char(32);
  Algorithm  char(8);
  Issuer     char(128);
  Subject    char(128);
  Audience   char(128);
  ExpiSecs   int(10);
  Jti        char(36);
  JwtOut     char(8192);
end-pr;

dcl-pr GETJWTCFG extpgm('GETJWTCFG');
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
end-pr;

//--------------------------------------------------------------
// Local prototypes
//--------------------------------------------------------------
dcl-pr UrlEncode varchar(8192);
  inString varchar(4096) const;
end-pr;

dcl-pr BuildRequestBody varchar(12000);
  Jwt   varchar(8192) const;
  Scope varchar(512)  const;
end-pr;

//--------------------------------------------------------------
// SQL options
//--------------------------------------------------------------
exec sql
  Set Option
    Commit    = *None,
    CloSqlCsr = *EndMod,
    DatFmt    = *ISO,
    Naming    = *Sys;

//--------------------------------------------------------------
// Token response mapping
//--------------------------------------------------------------
dcl-ds DsToken qualified;
  access_token      varchar(4096) inz('');
  expires_in        int(10)       inz(0);
  token_type        varchar(64)   inz('');
  scope             varchar(512)  inz('');
  error             varchar(128)  inz('');
  error_description varchar(1024) inz('');
end-ds;

//--------------------------------------------------------------
// Main
//--------------------------------------------------------------
dcl-proc Main;

  dcl-pi Main;
    ParmJwtLabel    char(36);
    ParmAccessToken char(4096);
    ParmExpiresIn   int(10);
    ParmError       char(256);
    ParmHttpRc      int(10);
  end-pi;

  dcl-c ClientAssertionType 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer';

  dcl-s Issuer128      char(128)    inz(*blanks);
  dcl-s Subject128     char(128)    inz(*blanks);
  dcl-s Audience128    char(128)    inz(*blanks);
  dcl-s CfgKSFile      char(10)     inz(*blanks);
  dcl-s CfgKSLib       char(10)     inz(*blanks);
  dcl-s CfgKeyLabel    char(32)     inz(*blanks);
  dcl-s CfgAudience256 char(256)    inz(*blanks);
  dcl-s CfgAlg10       char(10)     inz(*blanks);
  dcl-s Alg8           char(8)      inz(*blanks);
  dcl-s CfgFound       char(1)      inz('N');
  dcl-s CfgMsg         char(78)     inz(*blanks);
  dcl-s CfgExpSecs     int(10)      inz(0);
  dcl-s Jti            char(36)     inz(*blanks);
  dcl-s JwtOut         char(8192)   inz(*blanks);
  dcl-s JwtTrim        varchar(8192) inz('');
  dcl-s RequestBody    varchar(12000) inz('');
  dcl-s ResponseBody   varchar(16000) inz('');
  dcl-s JsonOptions    varchar(128) inz('doc=string case=convert');
  dcl-s ScopeV         varchar(512) inz('openid');

  // Clear outputs first.
  ParmAccessToken = *blanks;
  ParmExpiresIn   = 0;
  ParmError       = *blanks;
  ParmHttpRc      = 0;

  if %trim(ParmJwtLabel) = *blanks;
    ParmError = 'JWT label is required.';
    return;
  endif;

  callp GETJWTCFG(ParmJwtLabel
                : CfgKSFile
                : CfgKSLib
                : CfgKeyLabel
                : CfgAlg10
                : Issuer128
                : Subject128
                : CfgAudience256
                : CfgExpSecs
                : CfgFound
                : CfgMsg);

  if CfgFound <> 'Y';
    if %trim(CfgMsg) <> '';
      ParmError = %subst(%trim(CfgMsg) : 1 : 256);
    else;
      ParmError = 'No JWT config found for label=' + %trim(ParmJwtLabel);
    endif;
    return;
  endif;

  if CfgExpSecs <= 0;
    ParmError = 'JWT config has invalid token life (EXPIRY_SEC).';
    return;
  endif;

  if %trim(Issuer128) = *blanks;
    ParmError = 'JWT config issuer is required.';
    return;
  endif;

  if %trim(Subject128) = *blanks;
    Subject128 = Issuer128;
  endif;

  if %trim(CfgAudience256) = *blanks;
    ParmError = 'JWT config audience is required (endpoint URL).';
    return;
  endif;

  // JWTGEN currently accepts 128-char iss/sub/aud parameters.
  if %len(%trimr(Issuer128)) > 128;
    ParmError = 'Issuer length exceeds JWTGEN 128-char limit.';
    return;
  endif;
  if %len(%trimr(Subject128)) > 128;
    ParmError = 'Subject length exceeds JWTGEN 128-char limit.';
    return;
  endif;
  if %len(%trimr(CfgAudience256)) > 128;
    ParmError = 'Audience length exceeds JWTGEN 128-char limit.';
    return;
  endif;

  Audience128 = %trimr(CfgAudience256);
  Alg8 = %subst(%trimr(CfgAlg10) : 1 : 8);

  if %trim(Alg8) = *blanks;
    ParmError = 'JWT config algorithm is required.';
    return;
  endif;

  exec sql
    set :Jti = qsys2.generate_uuid();

  callp JWTGEN(CfgKSFile
             : CfgKSLib
             : CfgKeyLabel
             : Alg8
             : Issuer128
             : Subject128
             : Audience128
             : CfgExpSecs
             : Jti
             : JwtOut);

  JwtTrim = %trimr(JwtOut);
  if JwtTrim = '';
    ParmError = 'JWT generation failed (empty token).';
    return;
  endif;

  RequestBody = BuildRequestBody(JwtTrim : ScopeV);

  http_setauth(HTTP_AUTH_NONE : ' ' : ' ');

  ParmHttpRc = http_req('POST'
                      : %trim(CfgAudience256)
                      : *omit
                      : ResponseBody
                      : *omit
                      : RequestBody
                      : 'application/x-www-form-urlencoded');

  if ParmHttpRc <> 1;
    ParmError = 'Token endpoint HTTP request failed.';
    return;
  endif;

  monitor;
    data-into DsToken %data(ResponseBody : JsonOptions)
                     %parser('YAJLINTO');
  on-error;
    ParmError = 'Unable to parse token JSON response.';
    return;
  endmon;

  if %trim(DsToken.access_token) = '';
    if %trim(DsToken.error_description) <> '';
      ParmError = %subst(%trim(DsToken.error_description) : 1 : 256);
    elseif %trim(DsToken.error) <> '';
      ParmError = %subst(%trim(DsToken.error) : 1 : 256);
    else;
      ParmError = 'Token response missing access_token.';
    endif;
    return;
  endif;

  ParmAccessToken = %subst(DsToken.access_token : 1 : 4096);
  ParmExpiresIn   = DsToken.expires_in;

  *inlr = *on;

end-proc;

//--------------------------------------------------------------
// Build form-urlencoded token request body
//--------------------------------------------------------------
dcl-proc BuildRequestBody;
  dcl-pi *n varchar(12000);
    Jwt   varchar(8192) const;
    Scope varchar(512)  const;
  end-pi;

  dcl-c ClientAssertionType 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer';
  dcl-s Out varchar(12000);

  Out = 'client_assertion=' + UrlEncode(Jwt)
      + '&client_assertion_type=' + UrlEncode(ClientAssertionType)
      + '&grant_type=' + UrlEncode('client_credentials');

  if %trim(Scope) <> '';
    Out += '&scope=' + UrlEncode(Scope);
  endif;

  return Out;
end-proc;

//--------------------------------------------------------------
// SQL URL encoding helper
//--------------------------------------------------------------
dcl-proc UrlEncode;
  dcl-pi *n varchar(8192);
    inString varchar(4096) const;
  end-pi;

  dcl-s Utf8In   varchar(4096) ccsid(*utf8);
  dcl-s Utf8Out  varchar(8192) ccsid(*utf8);
  dcl-s EbcOut   varchar(8192);

  Utf8In = inString;
  exec sql set :Utf8Out = URL_ENCODE(:Utf8In);
  EbcOut = Utf8Out;

  return EbcOut;
end-proc;
