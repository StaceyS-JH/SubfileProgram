**free
ctl-opt option(*srcstmt : *nodebugio);
ctl-opt dftactgrp(*NO) actgrp(*new);
ctl-opt bnddir('JHIGNM':'JHBIND':'HBSBIND');
ctl-opt main(HBSHANDLR);

// 11/05/25 #1184229 S Smith - BSL Subsystem Resiliency
// 04/23/23 #        V Everett - expand HBSSBSCTL
// 11/27/23 #1178316 S Smith - remove allocate and deallocate
// 06/05/23 Greene   #1176052 - Start/end fi changes
// 09/15/23 #1177741 S Smith - CL Calling program
// 09/05/23 #1177516 S Smith - psds from hbstools
// 06/21/23 #1177077 S Smith - changes to process work types from
//                             HBSWORK
// 12/29/22          MCollins  - Added Push events for Banno Biz
//  7/22/22                    - modified for HBSTOOLS mishap
//  5/24/22                    - reworked and copied into BSLTEST
//  5/24/22 #xxxxxxx MCollins  - Handler program to call services
//
//  NetTeller JSON Push Example
//
// ------------------------------------------------------- //
// THIS PROGRAM IS PART OF SILVERLAKE SYSTEM (R)           //
// Copyright 1988-2019 by:                                 //
//                     JACK HENRY & ASSOCIATES, INC.       //
//                     MONETT, MISSOURI  65708             //
// ------------------------------------------------------- //

/include qcpysrc,yajl_H
/define HBSTOOLS_psds
/include qcpysrc,hbstools
/undefine HBSTOOLS_psds
/define HBSSBSCTL
/include qcpysrc,hbsstand
/undefine HBSSBSCTL

//---------------------------------------------------------
// Procedure definitions
//---------------------------------------------------------

dcl-pr CallSrvc;
  pReqCtx pointer const;
end-pr;

dcl-pr GetPushSrvc ind;
  pSrvcNam char(10) const;
  pSrvcPath char(200);
end-pr;

dcl-pr InitPgm ind end-pr;

dcl-pr HandleTestMode;
  pRcvGUID char(46) const;
end-pr;

dcl-pr JsonError varchar(2000000);
  pErrNum int(10) const;
  pReqCtx pointer const;
end-pr;

dcl-pr LoadPath ind end-pr;

dcl-pr CallHostProgram Extpgm('HBSCHPC');
  inPtr pointer;
  outPtr pointer;
  Service char(40);
  Version char(40);
  HostPgm char(10);
  RtnOpts char(40);
end-pr;

dcl-pr CreateNTDataQueues Extpgm('HBSNTDQC');
end-pr;

dcl-pr SetPush end-pr;

dcl-pr UpdtStat;
  stat char(1) const;
end-pr;

dcl-pr VarReset end-pr;

dcl-pr SendReqSuccess;
  pReqCtx pointer const;
end-pr;

dcl-pr SendReqError;
  pErrNum int(10) const;
  pReqCtx pointer const;
end-pr;

dcl-pr WrtDtaq;
  pDQname char(10) const;
  pDQDta varchar(36) const;
end-pr;

dcl-pr WrtTrans;
  pReqCtx pointer const;
  pStatus char(10) const;
end-pr;

dcl-pr WrtSend;
  pReqCtx pointer const;
  pService char(200) const;
  pInPtr pointer const;
  pAttempt packed(3) const;
  pStat char(1) const options(*nopass);
end-pr;

// Need to add this to a copy book
dcl-pr GetWorkData int(10);
  WorkType char(2) const;
  inGuid char(36) const;
  pVersion likeds(dsVersion);
  ReceiveData pointer value;
end-pr;

// Check Controller queue
dcl-pr CheckKeyQue int(10);
  p_dtaqnm char(10) const;
  p_dtaqlib char(10) const;
  p_keydata char(10) const;
end-pr;

//---------------------------------------------------------
// Data Structures
//---------------------------------------------------------

dcl-ds PathLst qualified dim(200);
  p_srvcname char(40);
  p_srvcpath char(200);
end-ds;

dcl-ds RecvDta;
  r_pguid char(36);
  r_aguid char(36);
  r_clob varchar(2000000);
end-ds;

dcl-ds RcvQDta;
  q_RcvGUID char(36);
  q_SndDtaq char(10);
end-ds;

dcl-ds ReqContext_t qualified template;
  RecvPtr pointer;
  RcvGuid char(36);
  SndDtaq char(10);
  HostService char(40);
  HostProgram char(10);
  RtnOpts char(40);
  SrvcPath char(200);
  IsTest ind;
  IsPush ind;
end-ds;

dcl-ds dsVersion extname('HBSVERSNV1') qualified template end-ds;
dcl-ds wVersion likeds(dsVersion);

dcl-ds ReqCtx likeds(ReqContext_t);

dcl-ds *n extname('JHAPAR') dtaara(*auto) end-ds;



//---------------------------------------------------------
// Stand alone fields
//---------------------------------------------------------

dcl-s end ind;
dcl-s gAttempt packed(3);
dcl-s gCntrlQ char(10);
dcl-s gPathIndx int(10);
// dcl-s gPrmPtr pointer(*proc);
dcl-s gInbound char(10);
dcl-s gPushQ char(10);
dcl-s gQlen packed(5);
dcl-s gQdata char(46);
dcl-s gVersion char(40);
dcl-s w_dtaqlib char(10);
dcl-s rc int(10);
dcl-s handllog char(200);
dcl-s w_dtaqctl char(10) inz('HBSCNTR');
dcl-s w_dta30 char(10);
dcl-s gCrtLogEvent char(1);
dcl-s gAppErrLog char(1);
dcl-s gVersionActive char(1);
dcl-s gRunAsTest char(1);


//--------------------------------------------------------
// Constants
//--------------------------------------------------------
// Carriage Return + Line Feed
// Hex value for CRLF pair
dcl-c CRLF const(x'0d25');

//---------------------------------------------------------
// HBSHANDLR - Mainline
//---------------------------------------------------------
dcl-proc HBSHANDLR;
dcl-pi *n;
  pRcvDtaq char(10) const;
  pRcvGUID char(46) const options(*nopass);
end-pi;

  exec sql
    set option
      Commit    = *none,
      CloSqlCsr = *endmod,
      Datfmt    = *iso;

  gInbound = pRcvDtaq;

  // Rcv data queue cannot be blanks
  if gInbound = *blanks;
    end = *on;
  else;
    // Initialize program
    end = InitPgm();

    // Test Mode or Normal
    if %passed(pRcvGUID);
      HandleTestMode(pRcvGUID);
      // Do not enter main processing, just end after call
      end = *on;
    else;
      ReqCtx.IsTest = *off;
    endif;

  endif;

  // Process requests
  dow end = *off;

    gQlen = %len(gQdata);
    gQdata = *blanks;
    VarReset();

    gQdata = hbstools_RecvDtq(gInbound:w_dtaqlib:gQlen:-1);

    RcvQDta = gQdata;
    if q_RcvGUID = 'CONTROL';
      rc = CheckKeyQue(gCntrlQ:w_dtaqlib:psjobnm);  // get control request for handler
      // check if instructions to end job and log
      if w_dta30 = 'ENDJOB';
        clear handllog;
        handllog = 'Handler Job#: ' + psjobnm +
                   %char(psjob#) + 'Normal End';
        hbstools_Commlog(660001:handllog);
        leave;    // leave handler - normal end
      else;
        iter;     // resume handler processing - no control request
      endif;
    endif;

    // No GUID
    if q_RcvGUID = *blanks;
      hbstools_CommLog(550012);
    endif;

    // Valid Data queue received, process request from client
    select;
    when hbstools_ChkDtaq(w_dtaqlib:q_SndDtaq);
      // If RtrvJSON();
      rc = GetWorkData('RQ'              //in
                      :q_RcvGuid        //in
                      :wVersion            //out
                      :%addr(RecvDta));
      if rc = 0;
        ReqCtx.HostService = wVersion.SrvcName;
        ReqCtx.HostProgram = wVersion.HostSrvc;
        gCrtLogEvent = wVersion.CrtLogEvnt;
        gAppErrLog = wVersion.AppErrLog;
        gVersionActive = wVersion.VersnActv;
        gRunAsTest = wVersion.RunAsTest;
        ReqCtx.RecvPtr = %addr(RecvDta);
        ReqCtx.RcvGuid = q_RcvGUID;
        ReqCtx.SndDtaq = q_SndDtaq;
        hbstools_CrtLog(r_aguid
                       :'GUIDLOG':''
                       :'550025':''
                       :Procname:psjobnm
                       :%char(psjob#):'Y');
        WrtTrans(%addr(ReqCtx):'N');
        SendReqSuccess(%addr(ReqCtx));
      else;
        ReqCtx.RecvPtr = %addr(RecvDta);
        ReqCtx.RcvGuid = q_RcvGUID;
        ReqCtx.SndDtaq = q_SndDtaq;
        SendReqError(rc:%addr(ReqCtx));
      endif;

    when %len(%trim(q_SndDtaq)) = 2;
      rc = GetWorkData(%trim(q_SndDtaq)  //in
                      :q_RcvGuid        //in
                      :wVersion            //out
                      :%addr(RecvDta));
      if rc = 0;
        ReqCtx.HostService = wVersion.SrvcName;
        ReqCtx.HostProgram = wVersion.HostSrvc;
        gCrtLogEvent = wVersion.CrtLogEvnt;
        gAppErrLog = wVersion.AppErrLog;
        gVersionActive = wVersion.VersnActv;
        gRunAsTest = wVersion.RunAsTest;
        //hbstools_Actvty(r_PGuid:r_AGuid:560000:
        //  ' Work Type ' + %trim(q_SndDtaq) + ' found');
        ReqCtx.RecvPtr = %addr(RecvDta);
        ReqCtx.RcvGuid = q_RcvGUID;
        ReqCtx.SndDtaq = q_SndDtaq;
        WrtTrans(%addr(ReqCtx):'N');
        SendReqSuccess(%addr(ReqCtx));
      else;
        ReqCtx.RecvPtr = %addr(RecvDta);
        ReqCtx.RcvGuid = q_RcvGUID;
        ReqCtx.SndDtaq = q_SndDtaq;
        SendReqError(rc:%addr(ReqCtx));
      endif;

    other;
      ReqCtx.HostProgram = q_SndDtaq;

      if GetPushSrvc(ReqCtx.HostProgram:ReqCtx.SrvcPath);
        // Set variables for push process
        SetPush();
        ReqCtx.RecvPtr = %addr(RecvDta);
        ReqCtx.RcvGuid = q_RcvGUID;
        ReqCtx.SndDtaq = q_SndDtaq;
        WrtTrans(%addr(ReqCtx):'N');
        SendReqSuccess(%addr(ReqCtx));
      else;
        // Bad Data queue, try to retrieve record and flag in error
        if q_SndDtaq = *blanks;
          q_SndDtaq = 'No Name';
        endif;

        hbstools_CrtLog(q_RcvGUID
                       :'GUIDLOG':''
                       :'550013':%trim(q_SndDtaq) + ' Not Found'
                       :Procname:psjobnm
                       :%char(psjob#):'Y');
      endif;
    endsl;

  enddo;

  return;

  on-exit;
    hbstools_CommLog(600000:psjobnm + 'Handler Job Ending Abnormally');
    *inlr = *on;

end-proc;

//---------------------------------------------------------
// HandleTestMode - Handle single test invocation flow
//---------------------------------------------------------
dcl-proc HandleTestMode;
dcl-pi *n;
  pRcvGUID char(46) const;
end-pi;

  ReqCtx.IsTest = *on;
  RcvQDta = pRcvGUID;

  if q_SndDtaq <> *blanks;
    if %len(%trim(q_SndDtaq)) = 2;
      rc = GetWorkData(%trim(q_SndDtaq)  //in
                      :q_RcvGuid        //in
                      :wVersion            //out
                      :%addr(RecvDta));
      if rc = 0;
        ReqCtx.HostService = wVersion.SrvcName;
        ReqCtx.HostProgram = wVersion.HostSrvc;
        gCrtLogEvent = wVersion.CrtLogEvnt;
        gAppErrLog = wVersion.AppErrLog;
        gVersionActive = wVersion.VersnActv;
        gRunAsTest = wVersion.RunAsTest;
        ReqCtx.RecvPtr = %addr(RecvDta);
        ReqCtx.RcvGuid = q_RcvGUID;
        ReqCtx.SndDtaq = q_SndDtaq;
        hbstools_CrtLog(r_aguid
                       :'GUIDLOG':''
                       :'560000':' Work Type ' + %trim(q_SndDtaq) + ' found'
                       :Procname:psjobnm
                       :%char(psjob#):'Y');
        WrtTrans(%addr(ReqCtx):'X');
        SendReqSuccess(%addr(ReqCtx));
      else;
        ReqCtx.RecvPtr = %addr(RecvDta);
        ReqCtx.RcvGuid = q_RcvGUID;
        ReqCtx.SndDtaq = q_SndDtaq;
        SendReqError(rc:%addr(ReqCtx));
      endif;
    else;
      ReqCtx.HostProgram = q_SndDtaq;
      if GetPushSrvc(ReqCtx.HostProgram:ReqCtx.SrvcPath);
        // Set variables for push process
        SetPush();
        ReqCtx.RecvPtr = %addr(RecvDta);
        ReqCtx.RcvGuid = q_RcvGUID;
        ReqCtx.SndDtaq = q_SndDtaq;
        SendReqSuccess(%addr(ReqCtx));
      endif;
    endif;
  else;
    rc = GetWorkData('RQ'              //in
                    :q_RcvGuid        //in
                    :wVersion            //out
                    :%addr(RecvDta));
    if rc = 0;
      ReqCtx.HostService = wVersion.SrvcName;
      ReqCtx.HostProgram = wVersion.HostSrvc;
      gCrtLogEvent = wVersion.CrtLogEvnt;
      gAppErrLog = wVersion.AppErrLog;
      gVersionActive = wVersion.VersnActv;
      gRunAsTest = wVersion.RunAsTest;
      ReqCtx.RecvPtr = %addr(RecvDta);
      ReqCtx.RcvGuid = q_RcvGUID;
      ReqCtx.SndDtaq = q_SndDtaq;
      hbstools_CrtLog(r_aguid
                     :'GUIDLOG':''
                     :'550025':''
                     :Procname:psjobnm
                     :%char(psjob#):'Y');
      WrtTrans(%addr(ReqCtx):'X');
      SendReqSuccess(%addr(ReqCtx));
    else;
      ReqCtx.RecvPtr = %addr(RecvDta);
      ReqCtx.RcvGuid = q_RcvGUID;
      ReqCtx.SndDtaq = q_SndDtaq;
      SendReqError(rc:%addr(ReqCtx));
    endif;
  endif;

  return;
end-proc;

//---------------------------------------------------------
// CallSrvc - Call Service from JSON request
//---------------------------------------------------------
dcl-proc CallSrvc;
dcl-pi *n;
  pReqCtx pointer const;
end-pi;

  dcl-s pInputPtr pointer;
  dcl-s pOutPtr pointer;
  dcl-s w_OutPtr pointer;
  dcl-ds wReqCtx likeds(ReqContext_t) based(pReqCtx);
  dcl-ds wReqData likeds(RecvDta) based(wReqCtx.RecvPtr);

  dcl-ds OutDS based(w_OutPtr);
    o_ParntGUID char(36);
    o_ActvtGUID char(36);
    o_RspJSON varchar(2000000);
    // I only need these parms if each service is going to return
    // the Origional values (If the child1 job does not write them to HBSRECV)
  end-ds;

  hbstools_CrtLog(wReqCtx.RcvGuid
                 :'GUIDLOG':''
                 :'550029':''
                 :Procname:psjobnm
                 :%char(psjob#):'Y');

  pInputPtr = wReqCtx.RecvPtr;
  //pOutPtr = %alloc(10);
  pOutPtr = *null;
  //pMsgPtr = %alloc(10);

  %subst(wReqCtx.RtnOpts:1:1) = gCrtLogEvent;
  %subst(wReqCtx.RtnOpts:2:1) = gAppErrLog;

  monitor;

    CallHostProgram(pInputPtr
                   :pOutPtr
                   :wReqCtx.HostService
                   :gVersion
                   :wReqCtx.HostProgram
                   :wReqCtx.RtnOpts);

    w_OutPtr = pOutPtr;

    if o_RspJSON = *blanks;
      //exsr ClearPtrs;
      wReqData.r_clob = JsonError(550022:pReqCtx);
      WrtSend(pReqCtx:'HBSHANDLR':wReqCtx.RecvPtr:1:'E');
      if pOutPtr <> *null;
        dealloc pOutPtr;
      endif;
      return;
    endif;

    // gAttempt = 1;
    gAttempt = 0;
    if %subst(wReqCtx.RtnOpts:40:1) <> 'N';
      WrtSend(pReqCtx:wReqCtx.HostProgram:pOutPtr:gAttempt);
    endif;
    hbstools_CrtLog(r_aguid
                   :'GUIDLOG':''
                   :'550034':''
                   :Procname:psjobnm
                   :%char(psjob#):'Y');
    if pOutPtr <> *null;
      dealloc pOutPtr;
    endif;

  on-error *all;
    wReqData.r_clob = JsonError(550021:pReqCtx);
    WrtSend(pReqCtx:'HBSHANDLR':wReqCtx.RecvPtr:1:'E');
    if pOutPtr <> *null;
      dealloc pOutPtr;
    endif;
    return;
  endmon;

  return;

end-proc;

//---------------------------------------------------------
// GetPushSrvc - Find Push service name from data queue
//---------------------------------------------------------
dcl-proc GetPushSrvc;
dcl-pi *n ind;
  pSrvcNam char(10) const;
  pSrvcPath char(200);
end-pi;

  dcl-s PathIndx int(10);
  dcl-s wTry int(10);

  if gPathIndx <= 0;
    if not LoadPath();  // No services loaded
      return *off;
    endif;
  endif;

  PathIndx = 0;

  for wTry = 1 to 2;
    PathIndx = %lookup(pSrvcNam:PathLst(*).p_srvcname:1);

    // If not found, try to load PathLst array again
    if PathIndx <= 0 and wTry = 1;
      LoadPath();
    else;
      leave;
    endif;

  endfor;

  if PathIndx > 0;
    pSrvcPath = PathLst(PathIndx).p_srvcpath;
    return *on;
  endif;

  return *off;

end-proc;

//---------------------------------------------------------
// InitPgm - Initialize the program
//---------------------------------------------------------
dcl-proc InitPgm;
dcl-pi *n ind end-pi;

  dsHBSSBSCTL = hbstools_GetDataArea('HBSSBSCTL':'*LIBL');
  w_dtaqlib = d_BankLib;

  // Make sure Rcv data queue exists if not create it
  if not hbstools_ChkDtaq(w_dtaqlib:gInbound);
    if not hbstools_CrtDtaq(w_dtaqlib:gInbound:46);
      hbstools_Commlog(550010:%trim(gInbound) + ' Not Found');
      return *on;
    endif;
  endif;

  // create control data queue if it does not exist
  gCntrlQ = 'HBSCNTR' + %char(%editc(jhbnkn:'X'));

  // Check for control data queue if not create
  if not hbstools_ChkDtaq(w_dtaqlib:gCntrlQ);
    if not hbstools_CrtDtaq(w_dtaqlib:gCntrlQ:10);
      hbstools_CommLog(550011:%trim(gCntrlQ) + ' Not Found');
      return *on;
    endif;
  endif;

  // create push data queue if it does not exist
  gPushQ = 'HBS' + %char(%editc(jhbnkn:'X')) + 'SQ01';

  // Check for push data queue if not create
  if not hbstools_ChkDtaq(w_dtaqlib:gPushQ);
    if not hbstools_CrtDtaq(w_dtaqlib:gPushQ:36);
      hbstools_CommLog(550013:%trim(gPushQ) + ' Not Found');
      return *on;
    endif;
  endif;

  exec sql
    declare PathCSR cursor
      for select hstsrvc, header
        from hbhsts;

  LoadPath();

  gVersion = 'HBSVersion1.0';

  CreateNTDataQueues();

  //   Exec SQL
  //      Declare VrsnCSR cursor
  //        For Select SrvcName, HostSrvc
  //          From HBSVERSN
  //          where Version = :gVersion;

  // Load list of services into array
  //   If Loadsrvcs();
  return *off;
  //   else;
  //     return *on;
  //   endif;

end-proc;

//---------------------------------------------------------
// JsonError - Create JSON error response
//---------------------------------------------------------
dcl-proc JsonError;
dcl-pi *n varchar(2000000);
  pErrNum int(10) const;
  pReqCtx pointer const;
end-pi;

  dcl-ds wErrDsc likeds(LogDesc_t);
  dcl-ds wReqCtx likeds(ReqContext_t) based(pReqCtx);
  dcl-ds wReqData likeds(RecvDta) based(wReqCtx.RecvPtr);
  dcl-s wInner varchar(2000);
  dcl-s yMsg   varchar(512);

  dcl-ds wErrBody qualified;
    dcl-ds ActivityTracking;
      ActivityId       varchar(36);
      ParentActivityId varchar(36);
    end-ds;
    num_ResponseDetailCollection int(10);
    dcl-ds ResponseDetailCollection dim(1);
      ResponseCode    int(10);
      ResponseMessage varchar(512);
    end-ds;
    Success ind;
  end-ds;

  hbstools_CrtLog(wReqData.r_aguid
                 :'GUIDLOG':''
                 :%char(pErrNum):''
                 :Procname:psjobnm
                 :%char(psjob#):'Y');

  wErrDsc = hbstools_GetDsc(pErrNum);

  yMsg = 'HBSHANDLR - ' + %trim(wErrDsc.Desc);

  wErrBody.ActivityTracking.ActivityId         = %trimr(wReqData.r_pguid);
  wErrBody.ActivityTracking.ParentActivityId   = %trimr(wReqData.r_aguid);
  wErrBody.num_ResponseDetailCollection        = 1;
  wErrBody.ResponseDetailCollection(1).ResponseCode    = pErrNum;
  wErrBody.ResponseDetailCollection(1).ResponseMessage = %trimr(yMsg);
  wErrBody.Success = *off;

  data-gen wErrBody %data(wInner : 'doc=string output=clear countprefix=num_')
                    %gen('YAJLDTAGEN');

  return '{"BaseRequest":' + %trimr(wReqData.r_clob) + ',' + %subst(wInner:2);

end-proc;

//---------------------------------------------------------
// LoadPath - Load data structure with client service paths
//---------------------------------------------------------
dcl-proc LoadPath;
dcl-pi *n ind end-pi;

  dcl-s FindPath ind;

  FindPath = *off;

  clear PathLst;

  exec sql
    open PathCSR;

  exec sql
    fetch next
    from PathCsr for 200 rows
      into :PathLst;

  if sqlstate = '02000' or
    SQLerrd(3) <= 0;
    FindPath = *off;
  endif;

  if SQLerrd(3) > 0;
    gPathIndx = SQLerrd(3);
    FindPath = *on;
  else;
    gPathIndx = 0;
    FindPath = *off;
  endif;

  exec sql
    close PathCSR;

  return FindPath;

end-proc;

//---------------------------------------------------------
// SetPush - Set variables for push request
//---------------------------------------------------------
dcl-proc SetPush;

  q_SndDtaq = gPushQ;
  r_aguid = q_RcvGUID;
  r_pguid = hbstools_CrtGuid();
  r_clob = *blanks;
  ReqCtx.IsPush = *on;

  return;

end-proc;

//---------------------------------------------------------
// UpdtStat - update status of incoming request
//---------------------------------------------------------
dcl-proc UpdtStat;
dcl-pi *n;
  p_stat char(1) const;
end-pi;

  dcl-s w_stat char(1);
  dcl-ds wReqData likeds(RecvDta) based(ReqCtx.RecvPtr);

  w_stat = p_stat;

  exec sql
    update HBSTRANS set HTSNDSTS = :p_stat
      where HTGUID = :wReqData.r_pguid;

  if sqlstate <> '00000';
    hbstools_CrtLog(wReqData.r_aguid
                   :'GUIDLOG':''
                   :'550032':''
                   :Procname:psjobnm
                   :%char(psjob#):'Y');
  endif;

  hbstools_CrtLog(wReqData.r_aguid
                 :'GUIDLOG':''
                 :'550033':''
                 :Procname:psjobnm
                 :%char(psjob#):'Y');

  return;

end-proc;

//---------------------------------------------------------
// VarReset - Reset working global fields
//---------------------------------------------------------
dcl-proc VarReset;

  clear RecvDta;
  clear RcvQdta;
  clear ReqCtx;

  return;

end-proc;

//---------------------------------------------------------
// WrtDtaq - Write outgoing GUID to Send Data queue
//---------------------------------------------------------
dcl-proc WrtDtaq;
dcl-pi *n;
  pDQname char(10) const;
  pDQDta varchar(36) const;
end-pi;

  dcl-s w_dqlen packed(5);

  w_dqlen = %len(pDQDta);

  if not hbstools_ChkDtaq(w_dtaqlib:pDQname);
    if not hbstools_CrtDtaq(w_dtaqlib:pDQname:w_dqlen);
      hbstools_CrtLog(''
                     :'GUIDLOG':''
                     :'550025':''
                     :Procname:psjobnm
                     :%char(psjob#):'Y');
      return;
    endif;
  endif;

  hbstools_SendDtq(pDQname:w_dtaqlib:w_dqlen:pDQDta);

  return;

end-proc;

//---------------------------------------------------------
// SendReqSuccess - call service
//---------------------------------------------------------
dcl-proc SendReqSuccess;
dcl-pi *n;
  pReqCtx pointer const;
end-pi;

  CallSrvc(pReqCtx);
  return;

end-proc;

//---------------------------------------------------------
// SendReqError - build/send error response
//---------------------------------------------------------
dcl-proc SendReqError;
dcl-pi *n;
  pErrNum int(10) const;
  pReqCtx pointer const;
end-pi;

  dcl-ds wReqCtx likeds(ReqContext_t) based(pReqCtx);
  dcl-ds wReqData likeds(RecvDta) based(wReqCtx.RecvPtr);

  wReqData.r_clob = JsonError(pErrNum:pReqCtx);
  WrtSend(pReqCtx:'HBSHANDLR':wReqCtx.RecvPtr:1:'E');
  return;

end-proc;

//---------------------------------------------------------
// WrtTrans - Write master transaction record
//---------------------------------------------------------
dcl-proc WrtTrans;
dcl-pi *n;
  pReqCtx pointer const;
  pStatus char(10) const;
end-pi;

  dcl-ds wReqCtx likeds(ReqContext_t) based(pReqCtx);
  dcl-ds wReqData likeds(RecvDta) based(wReqCtx.RecvPtr);

  // HBSTRANS was already inserted by HBSCHILD1 - just update the service fields
  exec sql
    update HBSTRANS
       set HTSNAME   = :wReqCtx.HostService,
           HTPNAME   = :wReqCtx.HostProgram,
           HTSNDSTS  = :pStatus
     where HTGUID = :wReqData.r_pguid;

  if sqlstate <> '00000';
    hbstools_CrtLog(wReqData.r_aguid
                   :'GUIDLOG':''
                   :'550028':''
                   :Procname:psjobnm
                   :%char(psjob#):'Y');
  endif;

  return;
end-proc;


//---------------------------------------------------------
// WrtSend - Write to HBSSEND to be sent
//---------------------------------------------------------
dcl-proc WrtSend;
dcl-pi *n;
  pReqCtx pointer const;
  pService char(200) const;
  pInPtr pointer const;
  pAttempt packed(3) const;
  pStat char(1) const options(*nopass);
end-pi;

  dcl-s SqlJSON sqltype(CLOB:2000000) inz('');
  dcl-ds wReqCtx likeds(ReqContext_t) based(pReqCtx);
  dcl-ds wReqData likeds(RecvDta) based(wReqCtx.RecvPtr);

  dcl-ds wOutDta based(pInPtr);
    wParntGUID char(36);
    wActvtGUID char(36);
    wRspJSON varchar(2000000);
  end-ds;

  dcl-s wStatUpd char(1);
  dcl-s wSndStat char(1);
  dcl-s wHeadr char(100);

  SqlJSON_len = %len(wRspJSON);
  if SqlJSON_len > 0;
    SqlJSON_data = %subst(wRspJSON:1:SqlJSON_len);
  else;
    SqlJSON_data = '';
  endif;

  // If a test, write to HBSSEND w/ status of 'X'
  if wReqCtx.IsTest = *off;
    wSndStat = 'N';
  else;
    wSndStat = 'X';
  endif;

  // Client request gets different header than push
  if wReqCtx.IsPush = *off;

    if %parms < 4;
      wStatUpd = 'Y';
      wHeadr = 'HTTP/1.1 200 OK' + CRLF +
               'Content-Type: application/json; charset=utf-8' +
               CRLF + 'Content-Length: ';
    else;
      wStatUpd = pStat;
      wHeadr = 'HTTP/1.1 400 - Bad Request' + CRLF +
               'Content-Type: application/json; charset=utf-8' +
               CRLF + 'Content-Length: ';
    endif;
  else;
    if %parms = 4;
      wSndStat = pStat;
    endif;

    // Push items get path to service for processing
    wHeadr = %trimr(wReqCtx.SrvcPath);
  endif;

  exec sql
    insert into HBRESP (HSGUID, HSATTMPT, HSHEADER, HSBODY)
         values (:wReqData.r_pguid, :pAttempt, :wHeadr, :SqlJSON);

  if SQLstate = '00000';

    // Do not write to send data queue if running test
    if wReqCtx.IsTest = *off;

      // If a client request or a push request w/o error
      // update data queue with GUID
      if wReqCtx.IsPush = *off or
        (wReqCtx.IsPush = *on and wSndStat <> 'E');
        WrtDtaq(wReqCtx.SndDtaq:wReqData.r_pguid);
      endif;
    else;
      // Update test trans with X
      wStatUpd = 'X';
    endif;

    hbstools_CrtLog(wActvtGUID
                   :'GUIDLOG':''
                   :'550027':''
                   :Procname:psjobnm
                   :%char(psjob#):'Y');

    UpdtStat(wStatUpd);
  else;
    hbstools_CrtLog(wActvtGUID
                   :'GUIDLOG':''
                   :'550027':''
                   :Procname:psjobnm
                   :%char(psjob#):'Y');
    UpdtStat('E');
  endif;

  return;

end-proc;

//--------------------------------------------------------
// CheckKeyQue - Check Controller queue and react to requests
//--------------------------------------------------------
dcl-proc CheckKeyQue;
dcl-pi *n int(10);
  p_dtaqnm char(10) const;
  p_dtaqlib char(10) const;
  p_keydata char(10) const;
end-pi;

  // receive only entries for B###C job matching the control job
  w_dta30 = *blanks;

  exec sql
    select cast(message_data as char(10))
      into :w_dta30
      from table(
        qsys2.receive_data_queue(
          data_queue         => :p_dtaqnm,
          data_queue_library => :p_dtaqlib,
          remove             => 'YES',
          wait_time          => 0,
          key_data           => :p_keydata,
          key_order          => 'EQ')) as dq
      fetch first 1 row only;

  if sqlstate = '02000';
    w_dta30 = *blanks;
  endif;

  return rc;

end-proc;
