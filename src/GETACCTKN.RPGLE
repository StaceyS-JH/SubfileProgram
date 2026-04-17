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
//        PARM( JwtLabel  AccessToken  ExpiresIn  ErrorMsg  HttpRc
//              [Scope] )
//
// Parm  1 - JwtLabel      36A   INPUT
// Parm  2 - AccessToken 4096A   OUTPUT
// Parm  3 - ExpiresIn     10I   OUTPUT
// Parm  4 - ErrorMsg     256A   OUTPUT (blank on success)
// Parm  5 - HttpRc        10I   OUTPUT (HTTPAPI transport rc)
// Parm  6 - Scope        512A   INPUT  OPTIONAL (blank = default)
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
  KSFile     char(10) const;
  KSLib      char(10) const;
  KeyLabel   char(32) const;
  Algorithm  char(10) const;
  Issuer     varchar(128) const options(*trim:*varsize);
  Subject    varchar(128) const options(*trim:*varsize);
  Audience   varchar(128) const options(*trim:*varsize);
  ExpiSecs   int(10) const;
  Jti        char(36) const;
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

dcl-pr ValidateConfig ind;
  Issuer128      char(128);
  Subject128     char(128);
  CfgAudience256 char(256) const;
  CfgAlg10       char(10) const;
  CfgExpSecs     int(10) const;
  Audience128    char(128);
  Alg8           char(10);
  ErrorMsg       char(256);
end-pr;

dcl-pr BuildClientAssertion ind;
  KSFile       char(10) const;
  KSLib        char(10) const;
  KeyLabel     char(32) const;
  Alg8         char(10) const;
  Issuer128    char(128) const;
  Subject128   char(128) const;
  Audience128  char(128) const;
  ExpSecs      int(10) const;
  JwtTrim      varchar(8192);
  ErrorMsg     char(256);
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

dcl-pr CallTokenEndpoint ind;
  Endpoint     varchar(2048) const;
  RequestBody  varchar(12000) const;
  ResponseBody varchar(16000);
  HttpRc       int(10);
  ErrorMsg     char(256);
end-pr;

dcl-pr ParseTokenJson ind;
  ResponseBody varchar(16000) const;
  JsonOptions  varchar(128) const;
  Token        likeds(DsToken);
end-pr;

//--------------------------------------------------------------
// Main
//--------------------------------------------------------------
dcl-proc Main;

  dcl-pi Main;
    ParmJwtLabel    char(36);                   // INPUT
    ParmAccessToken char(4096);                 // OUTPUT
    ParmExpiresIn   int(10);                    // OUTPUT
    ParmError       char(256);                  // OUTPUT
    ParmHttpRc      int(10);                    // OUTPUT
    ParmScope       char(512) options(*nopass); // OPTIONAL INPUT
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
  dcl-s Alg8           char(10)     inz(*blanks);
  dcl-s CfgFound       char(1)      inz('N');
  dcl-s CfgMsg         char(78)     inz(*blanks);
  dcl-s CfgExpSecs     int(10)      inz(0);
  dcl-s Jti            char(36)     inz(*blanks);
  dcl-s JwtOut         char(8192)   inz(*blanks);
  dcl-s JwtTrim        varchar(8192) inz('');
  dcl-s RequestBody    varchar(12000) inz('');
  dcl-s ResponseBody   varchar(16000) inz('');
  dcl-s HttpError      char(256)    inz(*blanks);
  dcl-s JsonOptions    varchar(128) inz('doc=string case=convert');
  dcl-s Scope          varchar(512) inz('openid');

  // Clear outputs first.
  ParmAccessToken = *blanks;
  ParmExpiresIn   = 0;
  ParmError       = *blanks;
  ParmHttpRc      = 0;

  if %passed(ParmScope);
    if %trim(ParmScope) <> *blanks;
      Scope = %trim(ParmScope);
    endif;
  endif;

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

  if not ValidateConfig(Issuer128
                      : Subject128
                      : CfgAudience256
                      : CfgAlg10
                      : CfgExpSecs
                      : Audience128
                      : Alg8
                      : ParmError);
    return;
  endif;

  if not BuildClientAssertion(CfgKSFile
                            : CfgKSLib
                            : CfgKeyLabel
                            : Alg8
                            : Issuer128
                            : Subject128
                            : Audience128
                            : CfgExpSecs
                            : JwtTrim
                            : ParmError);
    return;
  endif;

  RequestBody = BuildRequestBody(JwtTrim : Scope);

  if not CallTokenEndpoint(%trim(CfgAudience256)
                         : RequestBody
                         : ResponseBody
                         : ParmHttpRc
                         : HttpError);
    ParmError = HttpError;
    return;
  endif;

  if not ParseTokenJson(ResponseBody : JsonOptions : DsToken);
    ParmError = 'Unable to parse token JSON response.';
    return;
  endif;

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
// Execute OAuth token endpoint call
//--------------------------------------------------------------
dcl-proc CallTokenEndpoint;
  dcl-pi *n ind;
    Endpoint     varchar(2048) const;
    RequestBody  varchar(12000) const;
    ResponseBody varchar(16000);
    HttpRc       int(10);
    ErrorMsg     char(256);
  end-pi;

  dcl-s RespSnippet varchar(220) inz('');

  http_setauth(HTTP_AUTH_NONE : ' ' : ' ');

  HttpRc = http_req('POST'
                  : Endpoint
                  : *omit
                  : ResponseBody
                  : *omit
                  : RequestBody
                  : 'application/x-www-form-urlencoded');

  if HttpRc <> 1;
    ErrorMsg = 'Token endpoint transport failure rc=' + %trim(%char(HttpRc));
    if %trim(ResponseBody) <> '';
      RespSnippet = %subst(%trim(ResponseBody) : 1 : 220);
      ErrorMsg = %subst(%trim(ErrorMsg) + ' resp=' + RespSnippet : 1 : 256);
    endif;
  else;
    ErrorMsg = *blanks;
  endif;

  return (HttpRc = 1);
end-proc;

//--------------------------------------------------------------
// Parse token JSON response into result DS
//--------------------------------------------------------------
dcl-proc ParseTokenJson;
  dcl-pi *n ind;
    ResponseBody varchar(16000) const;
    JsonOptions  varchar(128) const;
    Token        likeds(DsToken);
  end-pi;

  clear Token;

  monitor;
    data-into Token %data(ResponseBody : JsonOptions)
                    %parser('YAJLINTO');
  on-error;
    return *off;
  endmon;

  return *on;
end-proc;

//--------------------------------------------------------------
// Validate retrieved config and normalize signer inputs
//--------------------------------------------------------------
dcl-proc ValidateConfig;
  dcl-pi *n ind;
    Issuer128      char(128);
    Subject128     char(128);
    CfgAudience256 char(256) const;
    CfgAlg10       char(10) const;
    CfgExpSecs     int(10) const;
    Audience128    char(128);
    Alg8           char(10);
    ErrorMsg       char(256);
  end-pi;

  if CfgExpSecs <= 0;
    ErrorMsg = 'JWT config has invalid token life (EXPIRY_SEC).';
    return *off;
  endif;

  if %trim(Issuer128) = *blanks;
    ErrorMsg = 'JWT config issuer is required.';
    return *off;
  endif;

  if %trim(Subject128) = *blanks;
    Subject128 = Issuer128;
  endif;

  if %trim(CfgAudience256) = *blanks;
    ErrorMsg = 'JWT config audience is required (endpoint URL).';
    return *off;
  endif;

  // JWTGEN currently accepts 128-char iss/sub/aud parameters.
  if %len(%trimr(Issuer128)) > 128;
    ErrorMsg = 'Issuer length exceeds JWTGEN 128-char limit.';
    return *off;
  endif;
  if %len(%trimr(Subject128)) > 128;
    ErrorMsg = 'Subject length exceeds JWTGEN 128-char limit.';
    return *off;
  endif;
  if %len(%trimr(CfgAudience256)) > 128;
    ErrorMsg = 'Audience length exceeds JWTGEN 128-char limit.';
    return *off;
  endif;

  Audience128 = %trimr(CfgAudience256);
  Alg8 = %trimr(CfgAlg10);

  if %trim(Alg8) = *blanks;
    ErrorMsg = 'JWT config algorithm is required.';
    return *off;
  endif;

  ErrorMsg = *blanks;
  return *on;
end-proc;

//--------------------------------------------------------------
// Build JWT client assertion using JWTGEN
//--------------------------------------------------------------
dcl-proc BuildClientAssertion;
  dcl-pi *n ind;
    KSFile       char(10) const;
    KSLib        char(10) const;
    KeyLabel     char(32) const;
    Alg8         char(10) const;
    Issuer128    char(128) const;
    Subject128   char(128) const;
    Audience128  char(128) const;
    ExpSecs      int(10) const;
    JwtTrim      varchar(8192);
    ErrorMsg     char(256);
  end-pi;

  dcl-s Jti    char(36)   inz(*blanks);
  dcl-s JwtOut char(8192) inz(*blanks);

  exec sql
    set :Jti = qsys2.generate_uuid();

  callp JWTGEN(KSFile
             : KSLib
             : KeyLabel
             : Alg8
             : Issuer128
             : Subject128
             : Audience128
             : ExpSecs
             : Jti
             : JwtOut);

  JwtTrim = %trimr(JwtOut);
  if JwtTrim = '';
    ErrorMsg = 'JWT generation failed (empty token).';
    return *off;
  endif;

  ErrorMsg = *blanks;
  return *on;
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
