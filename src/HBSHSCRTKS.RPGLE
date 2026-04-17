**FREE
//==============================================================
// Program:     HBSHSCRTKS
// Description: HBSHS-style host service that creates an IBM i
//              keystore by calling CRTKS.
//
// Call syntax:
//   CALL PGM(HBSHSCRTKS)
//        PARM( ReqPtr  ResPtr  Service  Version  RtnOpts )
//
// Request JSON (examples):
// {
//   "KsFile": "NTKS",
//   "KsLib": "BSLDAT220",
//   "MasterKeyId": 1,
//   "Description": "JWT key store",
//   "Authority": "*EXCLUDE"
// }
//==============================================================

ctl-opt dftactgrp(*no) actgrp(*caller)
        option(*srcstmt : *nodebugio)
        bnddir('HBSBIND');

//--------------------------------------------------------------
// Shared request/response package (HBSHS pattern)
//--------------------------------------------------------------
dcl-ds dsJSONPackage qualified template;
  PGUID char(36) inz('');
  AGUID char(36) inz('');
  clob  varchar(2000000) inz('');
end-ds;

dcl-s pReq pointer;
dcl-s pRes pointer;
dcl-ds dsRequest likeds(dsJSONPackage) based(pReq);
dcl-ds dsResponse likeds(dsJSONPackage);

//--------------------------------------------------------------
// Request / response models
//--------------------------------------------------------------
dcl-ds dsReqJSON qualified;
  KsFile      varchar(10) inz('');
  KsLib       varchar(10) inz('');
  MasterKeyId int(10)     inz(0);
  Description varchar(50) inz('');
  Authority   varchar(10) inz('');
end-ds;

dcl-ds dsResJSON qualified;
  Success         ind          inz(*off);
  ResponseCode    int(10)      inz(0);
  ResponseMessage varchar(256) inz('');
  KsFile          varchar(10)  inz('');
  KsLib           varchar(10)  inz('');
  MasterKeyId     int(10)      inz(0);
  BaseRequest     likeds(dsReqJSON);
end-ds;

//--------------------------------------------------------------
// External program prototype
//--------------------------------------------------------------
dcl-pr CRTKS extpgm('CRTKS');
  KSFile      char(10);
  KSLib       char(10);
  MasterKeyId int(10);
  Description char(50) options(*nopass);
  Authority   char(10) options(*nopass);
end-pr;

//--------------------------------------------------------------
// Local prototypes
//--------------------------------------------------------------
dcl-pr ParseJSON ind;
  pJSON varchar(2000000) const;
end-pr;

dcl-pr BuildResponseJSON;
end-pr;

//--------------------------------------------------------------
// Main
//--------------------------------------------------------------
dcl-proc Main;
  dcl-pi *n extpgm('HBSHSCRTKS');
    ReqPtr  pointer;
    ResPtr  pointer;
    Service char(40);
    Version char(40);
    RtnOpts char(40);
  end-pi;

  dcl-s WorkKsFile char(10) inz(*blanks);
  dcl-s WorkKsLib  char(10) inz(*blanks);
  dcl-s WorkDesc   char(50) inz(*blanks);
  dcl-s WorkAuth   char(10) inz(*blanks);

  pReq = ReqPtr;
  pRes = ResPtr;

  dsResponse.PGUID = dsRequest.PGUID;
  dsResponse.AGUID = dsRequest.AGUID;

  clear dsResJSON;

  if not ParseJSON(dsRequest.clob);
    dsResJSON.Success = *off;
    dsResJSON.ResponseCode = 9001;
    dsResJSON.ResponseMessage = 'Invalid request JSON.';
    BuildResponseJSON();
    ResPtr = %addr(dsResponse);
    return;
  endif;

  // Validate required fields.
  if %trim(dsReqJSON.KsFile) = '';
    dsResJSON.Success = *off;
    dsResJSON.ResponseCode = 1001;
    dsResJSON.ResponseMessage = 'KsFile is required.';
    BuildResponseJSON();
    ResPtr = %addr(dsResponse);
    return;
  endif;

  if %trim(dsReqJSON.KsLib) = '';
    dsResJSON.Success = *off;
    dsResJSON.ResponseCode = 1002;
    dsResJSON.ResponseMessage = 'KsLib is required.';
    BuildResponseJSON();
    ResPtr = %addr(dsResponse);
    return;
  endif;

  if dsReqJSON.MasterKeyId < 0 or dsReqJSON.MasterKeyId > 8;
    dsResJSON.Success = *off;
    dsResJSON.ResponseCode = 1003;
    dsResJSON.ResponseMessage = 'MasterKeyId must be 0 through 8.';
    BuildResponseJSON();
    ResPtr = %addr(dsResponse);
    return;
  endif;

  WorkKsFile = %trim(dsReqJSON.KsFile);
  WorkKsLib  = %trim(dsReqJSON.KsLib);
  WorkDesc   = %trim(dsReqJSON.Description);
  WorkAuth   = %trim(dsReqJSON.Authority);

  monitor;
    // Match CRTKS optional parm behavior.
    select;
      when %trim(WorkDesc) <> '' and %trim(WorkAuth) <> '';
        CRTKS(WorkKsFile : WorkKsLib : dsReqJSON.MasterKeyId : WorkDesc : WorkAuth);

      when %trim(WorkDesc) <> '';
        CRTKS(WorkKsFile : WorkKsLib : dsReqJSON.MasterKeyId : WorkDesc);

      when %trim(WorkAuth) <> '';
        CRTKS(WorkKsFile : WorkKsLib : dsReqJSON.MasterKeyId : *blanks : WorkAuth);

      other;
        CRTKS(WorkKsFile : WorkKsLib : dsReqJSON.MasterKeyId);
    endsl;

    dsResJSON.Success = *on;
    dsResJSON.ResponseCode = 0;
    dsResJSON.ResponseMessage = 'Keystore create request submitted to CRTKS.';

  on-error;
    dsResJSON.Success = *off;
    dsResJSON.ResponseCode = 9002;
    dsResJSON.ResponseMessage = 'CRTKS call failed. Check job log.';
  endmon;

  dsResJSON.KsFile = %trim(WorkKsFile);
  dsResJSON.KsLib = %trim(WorkKsLib);
  dsResJSON.MasterKeyId = dsReqJSON.MasterKeyId;

  BuildResponseJSON();

  ResPtr = %addr(dsResponse);
  *inlr = *on;

end-proc;

//--------------------------------------------------------------
// Parse request JSON into dsReqJSON
//--------------------------------------------------------------
dcl-proc ParseJSON;
  dcl-pi *n ind;
    pJSON varchar(2000000) const;
  end-pi;

  clear dsReqJSON;

  monitor;
    data-into dsReqJSON %data(pJSON
                              : 'doc=string case=convert -
                              allowextra=yes allowmissing=yes')
                        %parser('YAJLINTO');
  on-error;
    return *off;
  endmon;

  return *on;
end-proc;

//--------------------------------------------------------------
// Build response package JSON
//--------------------------------------------------------------
dcl-proc BuildResponseJSON;
  dcl-pi *n;
  end-pi;

  // Build JSON using YAJL generator (HBSHS standard pattern).
  dsResJSON.BaseRequest = dsReqJSON;

  %len(dsResponse.clob) = 0;
  dsResponse.clob = '';

  data-gen dsResJSON %data(dsResponse.clob
                           : 'doc=string output=clear')
                     %gen('YAJLDTAGEN');

end-proc;
