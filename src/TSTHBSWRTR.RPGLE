**free
//--------------------------------------------------------------
// TSTHBSWRTR - Test driver for HBSWRITER
//--------------------------------------------------------------
// Simulates what HBSCHILD1 (REQ) and HBSHANDLR (RESP) will do
// in Phase 2:
//   1. Inserts an HBSTRANS parent row
//   2. Creates a User Space in BSLCMJHA with test JSON
//   3. Sends the corresponding REQ/RESP message to HBSLOGDQ
//
// HBSWRITER must be running to process the messages and write
// to HBSREQ / HBRESP. After running, verify with:
//   SELECT * FROM HBSREQ  WHERE HRGUID = '<logged GUID>'
//   SELECT * FROM HBRESP  WHERE HSGUID = '<logged GUID>'
//
// NOTE: User Spaces are created in BSLCMJHA (not QTEMP) so
//       that HBSWRITER (a different job) can access them.
//       HBSCHILD1 and HBSHANDLR must use the same convention.
//--------------------------------------------------------------
ctl-opt dftactgrp(*no) actgrp(*new)
        option(*srcstmt: *nodebugio)
        bnddir('JHBIND');

/define HBSTOOLS_psds
/include qcpysrc,hbstools
/undefine HBSTOOLS_psds
/define HBSSBSCTL
/include qcpysrc,hbsstand
/undefine HBSSBSCTL

//--------------------------------------------------------------
// SQL options
//--------------------------------------------------------------
exec sql
  Set Option
    Commit    = *None,
    CloSqlCsr = *EndMod,
    DatFmt    = *ISO;

//--------------------------------------------------------------
// Data Queue Message Structure (must match HBSWRITER dsLogMsg)
//--------------------------------------------------------------
dcl-ds dsLogMsg qualified;
  lm_Type    char(4);
  lm_Guid    char(36);
  lm_UsName  char(10);
  lm_UsLib   char(10);
  lm_BodyLen int(10);
  lm_Attmpt  packed(3:0);
  lm_HdrLen  int(10);
  lm_Header  char(1024);
end-ds;

//--------------------------------------------------------------
// API Error DS
//--------------------------------------------------------------
dcl-ds dsApiErr qualified;
  BytesPrv  int(10) inz(%size(dsApiErr));
  BytesAvl  int(10);
  MsgId     char(7);
            char(1);
  MsgDta    char(256);
end-ds;

//--------------------------------------------------------------
// User Space API Prototypes
//--------------------------------------------------------------
dcl-pr QUSCRTUS extpgm('QUSCRTUS');
  QualName  char(20) const;
  ExtAttr   char(10) const;
  InitSize  int(10)  const;
  InitVal   char(1)  const;
  PubAuth   char(10) const;
  TextDesc  char(50) const;
  Replace   char(10) const;
  ErrCode   likeds(dsApiErr);
end-pr;

dcl-pr QUSPTRUS extpgm('QUSPTRUS');
  QualName  char(20) const;
  SpacePtr  pointer;
  ErrCode   likeds(dsApiErr);
end-pr;

dcl-pr QUSDLUS extpgm('QUSDLUS');
  QualName  char(20) const;
  ErrCode   likeds(dsApiErr);
end-pr;

dcl-pr QSNDDTAQ extpgm('QSNDDTAQ');
  DtaqName  char(10) const;
  DtaqLib   char(10) const;
  DtaLen    packed(5:0) const;
  Dta       char(32512) const options(*varsize);
end-pr;

//--------------------------------------------------------------
// Working variables
//--------------------------------------------------------------
dcl-s w_dtaqlib   char(10);
dcl-s w_guid      char(36);
dcl-s w_usName    char(10);
dcl-s w_usQual    char(20);
dcl-s w_usPtr     pointer;
dcl-s w_bodyRaw   char(2000000) based(w_usPtr);
dcl-s w_reqJson   varchar(2000);
dcl-s w_respJson  varchar(2000);
dcl-s w_reqHdr    varchar(256);
dcl-s w_respHdr   varchar(256);
dcl-s w_msgLen    packed(5:0) inz(%size(dsLogMsg));

//--------------------------------------------------------------
// Read library from HBSSBSCTL data area
//--------------------------------------------------------------
dsHBSSBSCTL = hbstools_GetDataArea('HBSSBSCTL':'*LIBL');
w_dtaqlib = d_BankLib;

//--------------------------------------------------------------
// Ensure HBSLOGDQ exists in the bank library
//--------------------------------------------------------------
if not hbstools_ChkDtaq(w_dtaqlib: 'HBSLOGDQ');
  if not hbstools_CrtDtaq(w_dtaqlib: 'HBSLOGDQ': %size(dsLogMsg));
    hbstools_CommLog(660005: 'TSTHBSWRTR: Could not create HBSLOGDQ in ' + w_dtaqlib);
    *inlr = *on;
    return;
  endif;
  hbstools_CommLog(660001: 'TSTHBSWRTR: Created HBSLOGDQ in ' + w_dtaqlib);
endif;

//--------------------------------------------------------------
// Generate GUID and build test payloads
//--------------------------------------------------------------
w_guid = hbstools_CrtGUID();

w_reqJson  = '{"ActivityId":"' + w_guid + '",' +
             '"ParentActivityId":"00000000-0000-0000-0000-000000000000",' +
             '"ServiceName":"HBSHS003",' +
             '"Request":"Test request payload from TSTHBSWRTR"}';

w_respJson = '{"Success":true,' +
             '"ActivityId":"' + w_guid + '",' +
             '"Response":"Test response payload from TSTHBSWRTR"}';

w_reqHdr  = 'POST /api/test HTTP/1.1' + x'0D25' +
            'Content-Type: application/json';

w_respHdr = 'HTTP/1.1 200 OK' + x'0D25' +
            'Content-Type: application/json';

hbstools_CommLog(660001: 'TSTHBSWRTR: Starting test with GUID=' + w_guid);

//--------------------------------------------------------------
// Insert HBSTRANS parent row
//--------------------------------------------------------------
exec sql
  insert into HBSTRANS
    (HTGUID, HTRQPGUID, HTRQAGUID, HTTYPE, HTRCVSTS, HTSNDSTS)
  values (:w_guid,
          '00000000-0000-0000-0000-000000000000',
          :w_guid,
          'RQ', 'R', 'N');

if sqlstate <> '00000';
  hbstools_CommLog(660005: 'TSTHBSWRTR: HBSTRANS insert failed SQLSTATE=' + sqlstate);
  *inlr = *on;
  return;
endif;

hbstools_CommLog(660001: 'TSTHBSWRTR: HBSTRANS row inserted');

//--------------------------------------------------------------
// REQ: Create User Space, write JSON, send DQ msg
// Name: 'RQ' + first 8 chars of GUID  e.g. RQa3f8c201
//--------------------------------------------------------------
w_usName = 'RQ' + %subst(w_guid: 1: 8);
w_usQual = w_usName + w_dtaqlib;

clear dsApiErr;
QUSCRTUS(w_usQual: 'HBSJSON   ': %len(w_reqJson): x'00':
         '*CHANGE   ': 'TSTHBSWRTR REQ test payload  ': '*NO       ': dsApiErr);
if dsApiErr.BytesAvl > 0;
  hbstools_CommLog(660005: 'TSTHBSWRTR: QUSCRTUS REQ failed MsgId=' + dsApiErr.MsgId);
  *inlr = *on;
  return;
endif;

clear dsApiErr;
QUSPTRUS(w_usQual: w_usPtr: dsApiErr);
if dsApiErr.BytesAvl > 0;
  hbstools_CommLog(660005: 'TSTHBSWRTR: QUSPTRUS REQ failed MsgId=' + dsApiErr.MsgId);
  *inlr = *on;
  return;
endif;

%subst(w_bodyRaw: 1: %len(w_reqJson)) = w_reqJson;

clear dsLogMsg;
dsLogMsg.lm_Type    = 'REQ ';
dsLogMsg.lm_Guid    = w_guid;
dsLogMsg.lm_UsName  = w_usName;
dsLogMsg.lm_UsLib   = w_dtaqlib;
dsLogMsg.lm_BodyLen = %len(w_reqJson);
dsLogMsg.lm_Attmpt  = 0;
dsLogMsg.lm_HdrLen  = %len(w_reqHdr);
dsLogMsg.lm_Header  = w_reqHdr;

QSNDDTAQ('HBSLOGDQ  ': w_dtaqlib: w_msgLen: dsLogMsg);

hbstools_CommLog(660001: 'TSTHBSWRTR: REQ message sent to HBSLOGDQ');

//--------------------------------------------------------------
// RESP: Create User Space, write JSON, send DQ msg
// Name: 'RS' + first 8 chars of GUID  e.g. RSa3f8c201
//--------------------------------------------------------------
w_usName = 'RS' + %subst(w_guid: 1: 8);
w_usQual = w_usName + w_dtaqlib;

clear dsApiErr;
QUSCRTUS(w_usQual: 'HBSJSON   ': %len(w_respJson): x'00':
         '*CHANGE   ': 'TSTHBSWRTR RESP test payload ': '*NO       ': dsApiErr);
if dsApiErr.BytesAvl > 0;
  hbstools_CommLog(660005: 'TSTHBSWRTR: QUSCRTUS RESP failed MsgId=' + dsApiErr.MsgId);
  *inlr = *on;
  return;
endif;

clear dsApiErr;
QUSPTRUS(w_usQual: w_usPtr: dsApiErr);
if dsApiErr.BytesAvl > 0;
  hbstools_CommLog(660005: 'TSTHBSWRTR: QUSPTRUS RESP failed MsgId=' + dsApiErr.MsgId);
  *inlr = *on;
  return;
endif;

%subst(w_bodyRaw: 1: %len(w_respJson)) = w_respJson;

clear dsLogMsg;
dsLogMsg.lm_Type    = 'RESP';
dsLogMsg.lm_Guid    = w_guid;
dsLogMsg.lm_UsName  = w_usName;
dsLogMsg.lm_UsLib   = w_dtaqlib;
dsLogMsg.lm_BodyLen = %len(w_respJson);
dsLogMsg.lm_Attmpt  = 1;
dsLogMsg.lm_HdrLen  = %len(w_respHdr);
dsLogMsg.lm_Header  = w_respHdr;

QSNDDTAQ('HBSLOGDQ  ': w_dtaqlib: w_msgLen: dsLogMsg);

hbstools_CommLog(660001: 'TSTHBSWRTR: RESP message sent to HBSLOGDQ');
hbstools_CommLog(660001: 'TSTHBSWRTR: Done. Verify results with GUID=' + w_guid);

*inlr = *on;
return;
