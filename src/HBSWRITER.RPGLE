**free
//--------------------------------------------------------------
// HBSWRITER - Asynchronous BSL Log Writer
//--------------------------------------------------------------
// Persistent background job. Blocks on HBSLOGDQ data queue,
// retrieves JSON payloads from User Spaces, and writes to
// HBSREQ or HBRESP. Deletes the User Space after each write.
//
// Send message type 'END ' to HBSLOGDQ to terminate gracefully.
//
// DQ message layout is defined by dsLogMsg below. Senders
// (HBSCHILD1 for REQ, HBSHANDLR for RESP) must use the same DS.
//--------------------------------------------------------------
ctl-opt dftactgrp(*no) actgrp('HBSWRITER')
        option(*srcstmt: *nodebugio)
        bnddir('JHBIND');

// 04/19/26 #1184229 S Smith - Rewrite: HBSRECV/HBSSEND to HBSREQ/HBRESP
//                             Persistent DQ listener replacing submitted job

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
// Data Queue Message Structure
// All senders must use this identical layout.
//--------------------------------------------------------------
dcl-ds dsLogMsg qualified;
  lm_Type    char(4);       // 'REQ ' - request, 'RESP' - response, 'END ' - terminate
  lm_Guid    char(36);      // HTGUID (primary correlation key)
  lm_UsName  char(10);      // User Space object name (max 10 chars)
  lm_UsLib   char(10);      // User Space library
  lm_BodyLen int(10);       // Byte length of JSON body stored in User Space
  lm_Attmpt  packed(3:0);   // Reserved - not used (attempt tracked in HBSTRANS.HTATTEMPTS)
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
dcl-pr QUSPTRUS extpgm('QUSPTRUS');
  QualName  char(20) const;
  SpacePtr  pointer;
  ErrCode   likeds(dsApiErr);
end-pr;

dcl-pr QUSDLUS extpgm('QUSDLUS');
  QualName  char(20) const;
  ErrCode   likeds(dsApiErr);
end-pr;

//--------------------------------------------------------------
// Forward procedure declarations
//--------------------------------------------------------------
dcl-pr ReadLogQue ind extproc(*dclcase);
  p_msg  char(%size(dsLogMsg));
end-pr;

dcl-pr WriteReq extproc(*dclcase);
  p_msg  likeds(dsLogMsg) const;
end-pr;

dcl-pr WriteResp extproc(*dclcase);
  p_msg  likeds(dsLogMsg) const;
end-pr;

dcl-pr CleanupUs extproc(*dclcase);
  p_qual char(20) const;
end-pr;

//--------------------------------------------------------------
// Module-level working variables
//--------------------------------------------------------------
dcl-s w_end    ind   inz(*off);
dcl-s w_msgraw char(%size(dsLogMsg));
dcl-s w_dtaqlib char(10);

//--------------------------------------------------------------
// Main processing loop
//--------------------------------------------------------------
// Read library from HBSSBSCTL data area
dsHBSSBSCTL = hbstools_GetDataArea('HBSSBSCTL':'*LIBL');
w_dtaqlib = d_BankLib;

dow not w_end;

  if ReadLogQue(w_msgraw);
    dsLogMsg = w_msgraw;
    select;
    when dsLogMsg.lm_Type = 'REQ ';
      WriteReq(dsLogMsg);
    when dsLogMsg.lm_Type = 'RESP';
      WriteResp(dsLogMsg);
    when dsLogMsg.lm_Type = 'END ';
      w_end = *on;
    endsl;
  endif;

enddo;

*inlr = *on;
return;

//--------------------------------------------------------------
// ReadLogQue - Block on HBSLOGDQ until a message arrives
//--------------------------------------------------------------
dcl-proc ReadLogQue;
dcl-pi *n ind;
  p_msg  char(%size(dsLogMsg));
end-pi;

dcl-s w_msglen int(10) inz(%size(dsLogMsg));

exec sql
  select cast(message_data as char(:w_msglen))
  into :p_msg
  from table(
      qsys2.receive_data_queue(
      data_queue         => 'HBSLOGDQ',
      data_queue_library => :w_dtaqlib,
      remove             => 'YES',
      wait_time          => -1)) as dq
  fetch first 1 row only;

if sqlstate <> '00000' and sqlstate <> '01000';
  return *off;
endif;

return *on;

end-proc;

//--------------------------------------------------------------
// WriteReq - Read User Space, insert request into HBSREQ
//--------------------------------------------------------------
dcl-proc WriteReq;
dcl-pi *n;
  p_msg  likeds(dsLogMsg) const;
end-pi;

dcl-s w_usQual  char(20);
dcl-s w_bodyPtr pointer;
dcl-s w_bodyRaw char(2000000) based(w_bodyPtr);
dcl-s w_body    sqltype(CLOB:2000000);

w_usQual = p_msg.lm_UsName + p_msg.lm_UsLib;
clear dsApiErr;
QUSPTRUS(w_usQual: w_bodyPtr: dsApiErr);
if dsApiErr.BytesAvl > 0;
  hbstools_CommLog(660005: 'HBSWRITER WriteReq: QUSPTRUS failed for ' + w_usQual);
  return;
endif;

w_body_len  = p_msg.lm_BodyLen;
w_body_data = %subst(w_bodyRaw: 1: p_msg.lm_BodyLen);

exec sql
  insert into HBSREQ (HRGUID, HRBODY)
  values (:p_msg.lm_Guid, :w_body);

if sqlstate <> '00000';
  hbstools_CommLog(660005: 'HBSWRITER WriteReq: insert failed SQLSTATE=' + sqlstate
                           + ' GUID=' + p_msg.lm_Guid);
endif;

CleanupUs(w_usQual);

end-proc;

//--------------------------------------------------------------
// WriteResp - Read User Space, insert response into HBRESP
//--------------------------------------------------------------
dcl-proc WriteResp;
dcl-pi *n;
  p_msg  likeds(dsLogMsg) const;
end-pi;

dcl-s w_usQual  char(20);
dcl-s w_bodyPtr pointer;
dcl-s w_bodyRaw char(2000000) based(w_bodyPtr);
dcl-s w_body    sqltype(CLOB:2000000);

w_usQual = p_msg.lm_UsName + p_msg.lm_UsLib;
clear dsApiErr;
QUSPTRUS(w_usQual: w_bodyPtr: dsApiErr);
if dsApiErr.BytesAvl > 0;
  hbstools_CommLog(660005: 'HBSWRITER WriteResp: QUSPTRUS failed for ' + w_usQual);
  return;
endif;

w_body_len  = p_msg.lm_BodyLen;
w_body_data = %subst(w_bodyRaw: 1: p_msg.lm_BodyLen);

exec sql
  insert into HBRESP (HSGUID, HSBODY)
  values (:p_msg.lm_Guid, :w_body);

if sqlstate <> '00000';
  hbstools_CommLog(660005: 'HBSWRITER WriteResp: insert failed SQLSTATE=' + sqlstate
                           + ' GUID=' + p_msg.lm_Guid);
endif;

CleanupUs(w_usQual);

end-proc;

//--------------------------------------------------------------
// CleanupUs - Delete User Space after write
//--------------------------------------------------------------
dcl-proc CleanupUs;
dcl-pi *n;
  p_qual char(20) const;
end-pi;

clear dsApiErr;
QUSDLUS(p_qual: dsApiErr);
if dsApiErr.BytesAvl > 0;
  hbstools_CommLog(660005: 'HBSWRITER CleanupUs: QUSDLUS failed for ' +
                           %trimr(%subst(p_qual: 1: 10)));
endif;

end-proc;
