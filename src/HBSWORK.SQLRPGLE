**free
ctl-opt option(*srcstmt : *nodebugio);
ctl-opt bnddir('HBSBIND');
ctl-opt nomain;

// 09/15/23 #1177741 S Smith - changes for CL calling program
// 09/05/23 #1177516 S Smith - psds from hbstools
// 06/21/23 #1177077 S Smith - HBSHANDLR Work Type processing
// BSL Rewrite - replaced HBSRECV/HBSSEND with HBSTRANS/HBSREQ/HBRESP
// ----------------------------------------------------- //
// This program is part of Silverlake System(R)          //
// Copyright 1988-2023 by: Jack Henry & Associates, Inc. //
//                         Monett, Missouri  65708       //
// ----------------------------------------------------- //

/define HBSTOOLS_psds
/include qcpysrc,hbstools
/undefine HBSTOOLS_psds

//---------------------------------------------------------
// Data Structures
//---------------------------------------------------------

dcl-ds RecvDta;
  r_pguid char(36);
  r_aguid char(36);
  r_clob varchar(2000000);
end-ds;

dcl-ds dsVersion extname('HBSVERSNV1') qualified template end-ds;
dcl-ds ServiceList likeds(dsVersion) dim(200);

dcl-ds SRSrvcMap qualified dim(200);
  sr_hstSvc char(10);
  sr_hstPgm char(10);
  sr_srvcNam char(40);
end-ds;

//---------------------------------------------------------
// Stand alone fields
//---------------------------------------------------------

dcl-s gListIndx int(10);
dcl-s gSRMapIndx int(10);
dcl-s gVersion char(40);

//---------------------------------------------------------
// GetWorkData - Main dispatcher
//---------------------------------------------------------
dcl-proc GetWorkData export;
dcl-pi *n int(10);
  pWorkType char(2) const;
  pInGuid char(36) const;
  pVersion likeds(dsVersion);
  pReceiveData pointer value;
end-pi;

  dcl-ds pRecvData likeds(RecvDta) based(pReceiveData);
  dcl-s wRc int(10);

  wRc = 0;

  gVersion = 'HBSVersion1.0';

  exec sql
    set option
      Commit    = *none,
      CloSqlCsr = *endmod,
      DynUsrPrf = *owner,
      DatFmt    = *iso;

  select;
    when pWorkType = 'RQ';
      wRc = GetRQWorkData(pInGuid
                         :pVersion
                         :pRecvData);
    when pWorkType = 'SR';
      wRc = GetSRWorkData(pInGuid
                         :pVersion
                         :pRecvData);
    when pWorkType = 'MN';
      wRc = GetMNWorkData(pInGuid
                         :pVersion
                         :pRecvData);
    when pWorkType = 'CI';
      wRc = GetCIWorkData(pInGuid
                         :pVersion
                         :pRecvData);
    other;
      // work type not defined
      wRc = -1;
  endsl;

  return wRc;

end-proc;

//---------------------------------------------------------
// GetSRWorkData - Get send-response work data
//   Queries HBRESP joined with HBSTRANS
//   wr_pguid    = HSGUID    (= HTGUID = w_guid2)
//   wr_aguid    = HSGUID    (= HTGUID = w_guid2)
//   wr_hshstsrv = HTPNAME   (host program name for SRSrvcMap lookup)
//   wr_sql_clob = HSBODY    (response JSON payload)
//---------------------------------------------------------
dcl-proc GetSRWorkData;
dcl-pi *n int(10);
  inGuid char(36) const;
  outVersion likeds(dsVersion);
  outData likeds(RecvDta);
end-pi;

  // outData is passed by reference via LIKEDS
  dcl-ds wSndRes;
    wr_pguid char(36);
    wr_aguid char(36);
    wr_hshstsrv char(10);
    wr_sql_clob sqltype(CLOB:2000000);
  end-ds;

  dcl-s wSRMapIdx int(10);
  dcl-s wTry int(10);

  clear wSndRes;

  exec sql
    select r.HSGUID, r.HSGUID, t.HTPNAME, r.HSBODY
      into :wSndRes
      from HBRESP r
      join HBSTRANS t on t.HTGUID = r.HSGUID
      where r.HSGUID = :inGuid;

  if sqlstate = '02000';
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550041;
  endif;

  if CheckSQLstate(sqlstate) = 'C';
    MsgHdlr(MessageType:GetSQLCode(sqlcode):MessageFile);
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550014;
  endif;

  outData.r_pguid = wr_pguid;
  outData.r_aguid = wr_aguid;

  // if clob field is empty or pointer not set, no JSON request
  if wr_sql_clob_len <= 0;
    return 550015;
  endif;

  outData.r_clob  = %subst(wr_sql_clob_data:1:wr_sql_clob_len);

  // Find service info from in-memory cache (avoids per-request join)
  if gSRMapIndx <= 0;
    if not LoadSRSrvcMap();
      outData.r_pguid = 'Not Available';
      outData.r_aguid = inGuid;
      return 550017;
    endif;
  endif;

  for wTry = 1 to 2;
    wSRMapIdx = %lookup(wr_hshstsrv:SRSrvcMap(*).sr_hstSvc:1);
    if wSRMapIdx <= 0 and wTry = 1;
      LoadSRSrvcMap();
    else;
      leave;
    endif;
  endfor;

  if wSRMapIdx <= 0;
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550017;
  endif;

  outVersion.SrvcName = SRSrvcMap(wSRMapIdx).sr_srvcNam;
  GetHostSrvc(outVersion);

  return 0;

end-proc;

//---------------------------------------------------------
// GetRQWorkData - Get receive-request work data
//   Queries HBSREQ joined with HBSTRANS
//   wr_pguid    = HRGUID     (HTGUID = w_guid2, the transaction key)
//   wr_aguid    = HTRQAGUID  (JSON ActivityId, for activity logging)
//   wr_header   = HRHEADER   (HTTP request header)
//   wr_sql_clob = HRBODY     (JSON request payload)
//---------------------------------------------------------
dcl-proc GetRQWorkData;
dcl-pi *n int(10);
  inGuid char(36) const;
  outVersion likeds(dsVersion);
  outData likeds(RecvDta);
end-pi;

  // outData is passed by reference via LIKEDS
  dcl-ds wRecv;
    wr_pguid char(36);
    wr_aguid char(36);
    wr_header varchar(5000);
    wr_sql_clob sqltype(CLOB:2000000);
  end-ds;

  dcl-s wRc int(10);

  clear wRecv;

  exec sql
    select r.HRGUID, t.HTRQAGUID,
           cast(r.HRHEADER as varchar(5000)),
           r.HRBODY
      into :wRecv
      from HBSREQ r
      join HBSTRANS t on t.HTGUID = r.HRGUID
      where t.HTRCVSTS = 'N'
        and r.HRGUID = :inGuid;

  if sqlstate = '02000';
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550041;
  endif;

  if CheckSQLstate(sqlstate) = 'C';
    MsgHdlr(MessageType:GetSQLCode(sqlcode):MessageFile);
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550014;
  endif;

  outData.r_pguid = wr_pguid;
  outData.r_aguid = wr_aguid;

  // if clob field is empty or pointer not set, no JSON request
  if wr_sql_clob_len <= 0;
    return 550015;
  endif;

  outData.r_clob  = %subst(wr_sql_clob_data:1:wr_sql_clob_len);

  // Find service name from JSON request header
  wRc = FindSrvc(wr_header
                :outVersion);
  if wRc <> 0;
    return wRc;
  endif;

  return 0;

end-proc;

//---------------------------------------------------------
// FindSrvc - Find Service Name from JSON request header
//---------------------------------------------------------
dcl-proc FindSrvc;
dcl-pi *n int(10);
  pRecvHdr char(5000) const;
  pVersion likeds(dsVersion);
end-pi;

  dcl-s wEPos int(10);
  dcl-s wSPos int(10);
  dcl-s wSrvcNam char(80);
  dcl-s wRc int(10);

  clear pVersion;

  // Scan for service name at end of header
  wEPos = %scan('HTTP/':pRecvHdr:7);

  if wEPos > 0;
    // New method to get service name
    wSPos = %scanr('/':%subst(pRecvHdr:1:wEPos));
    if wSPos > 0;
      wSPos += 1;
      wSrvcNam = %subst(pRecvHdr:wSPos:(wEPos - wSPos));
    else;
      wSrvcNam = *blanks;
    endif;
  else;
    wSrvcNam = *blanks;
  endif;

  select;
    when wSrvcNam = *blanks;
      return 550036;
    other;
      pVersion.SrvcName = wSrvcNam;
      wRc = GetHostSrvc(pVersion);
      if wRc <> 0;
        return 550017;
      else;
        return 0;  // success
      endif;
  endsl;

end-proc;

//---------------------------------------------------------
// GetHostSrvc - Find Host Service name from service list
//---------------------------------------------------------
dcl-proc GetHostSrvc;
dcl-pi *n int(10);
  pVersion likeds(dsVersion);
end-pi;

  dcl-s ListIndx int(10);
  dcl-s wAttmpt int(10);

  if gListIndx <= 0;
    LoadSrvcs();  // No services loaded
  endif;

  ListIndx = 0;

  for wAttmpt = 1 to 2;
    ListIndx = %lookup(pVersion.SrvcName:ServiceList(*).SrvcName:1);
    if ListIndx <= 0 and wAttmpt = 1;
      LoadSrvcs();
    else;
      leave;
    endif;
  endfor;

  if ListIndx > 0;
    pVersion = ServiceList(ListIndx);
    return 0;
  endif;

  return 1;

end-proc;

//---------------------------------------------------------
// LoadSrvcs - Load data structure with active services
//---------------------------------------------------------
dcl-proc LoadSrvcs;
dcl-pi *n ind end-pi;

  dcl-s FindSrvc ind;

  FindSrvc = *off;

  clear ServiceList;

  exec sql
    declare VrsnCSR cursor
      for select *
            from HBSVERSN
            where Version = :gVersion;

  exec sql
    open VrsnCSR;

  exec sql
    fetch next
    from VrsnCsr for 200 rows
      into :ServiceList;

  if sqlstate = '02000' or
    SQLerrd(3) <= 0;
    FindSrvc = *off;
  endif;

  if SQLerrd(3) > 0;
    gListIndx = SQLerrd(3);
    FindSrvc = *on;
  else;
    gListIndx = 0;
    FindSrvc = *off;
  endif;

  exec sql
    close VrsnCSR;

  return FindSrvc;

end-proc;

//---------------------------------------------------------
// LoadSRSrvcMap - Load SR host-service lookup cache
//---------------------------------------------------------
dcl-proc LoadSRSrvcMap;
dcl-pi *n ind end-pi;

  dcl-s FindEntry ind;

  FindEntry = *off;

  clear SRSrvcMap;

  exec sql
    declare SRSrvcCSR cursor
      for select hstsrvc, hostsrvc, srvcname
            from HBHSTS join HBSVERSN on sndrsps = srvcname;

  exec sql
    open SRSrvcCSR;

  exec sql
    fetch next
    from SRSrvcCSR for 200 rows
      into :SRSrvcMap;

  if sqlstate = '02000' or
    SQLerrd(3) <= 0;
    FindEntry = *off;
  endif;

  if SQLerrd(3) > 0;
    gSRMapIndx = SQLerrd(3);
    FindEntry = *on;
  else;
    gSRMapIndx = 0;
    FindEntry = *off;
  endif;

  exec sql
    close SRSrvcCSR;

  return FindEntry;

end-proc;

//---------------------------------------------------------
// GetMNWorkData - Get menu work data
//   Queries HBSREQ joined with HBSTRANS (same as GetRQWorkData)
//   wr_pguid    = HRGUID     (HTGUID = w_guid2, the transaction key)
//   wr_aguid    = HTRQAGUID  (JSON ActivityId, for activity logging)
//   wr_header   = HRHEADER   (used as service name for MN type)
//   wr_sql_clob = HRBODY     (JSON request payload)
//---------------------------------------------------------
dcl-proc GetMNWorkData;
dcl-pi *n int(10);
  inGuid char(36) const;
  outVersion likeds(dsVersion);
  outData likeds(RecvDta);
end-pi;

  // outData is passed by reference via LIKEDS
  dcl-ds wRecv;
    wr_pguid char(36);
    wr_aguid char(36);
    wr_header varchar(5000);
    wr_sql_clob sqltype(CLOB:2000000);
  end-ds;

  dcl-s wSrvcNam char(80);

  clear wRecv;

  exec sql
    select r.HRGUID, t.HTRQAGUID,
           cast(r.HRHEADER as varchar(5000)),
           r.HRBODY
      into :wRecv
      from HBSREQ r
      join HBSTRANS t on t.HTGUID = r.HRGUID
      where t.HTRCVSTS = 'N'
        and r.HRGUID = :inGuid;

  if sqlstate = '02000';
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550041;
  endif;

  if CheckSQLstate(sqlstate) = 'C';
    MsgHdlr(MessageType:GetSQLCode(sqlcode):MessageFile);
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550014;
  endif;

  outData.r_pguid = wr_pguid;
  outData.r_aguid = wr_aguid;

  // The service name is in the header
  wSrvcNam = %trim(wr_header);

  // if clob field is empty or pointer not set, no JSON request
  if wr_sql_clob_len <= 0;
    return 550015;
  endif;

  outData.r_clob  = %subst(wr_sql_clob_data:1:wr_sql_clob_len);

  outVersion.SrvcName = wSrvcNam;
  if GetHostSrvc(outVersion) <> 0;
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550017;
  endif;

  return 0;

end-proc;

//---------------------------------------------------------
// GetCIWorkData - Get CI work data (unchanged - uses HBSCI)
//---------------------------------------------------------
dcl-proc GetCIWorkData;
dcl-pi *n int(10);
  inGuid char(36) const;
  outVersion likeds(dsVersion);
  outData likeds(RecvDta);
end-pi;

  // outData is passed by reference via LIKEDS
  dcl-ds dsHBSCI;
    ci_pguid char(36);
    ci_aguid char(36);
    ci_service char(40);
    ci_sql_clob sqltype(CLOB:2000000);
  end-ds;

  dcl-s wSrvcNam char(40);

  clear dsHBSCI;

  exec sql
    select cipguid, ciaguid, cisrvc, cidata
      into :dsHBSCI
      from HBSCI
      where ciaguid = :inGuid;

  if sqlstate = '02000';
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550041;
  endif;

  if CheckSQLstate(sqlstate) = 'C';
    MsgHdlr(MessageType:GetSQLCode(sqlcode):MessageFile);
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550014;
  endif;

  outData.r_pguid = ci_pguid;
  outData.r_aguid = ci_aguid;

  // The service name is in the CI record
  wSrvcNam = %trim(ci_service);

  // if clob field is empty or pointer not set, no JSON request
  if ci_sql_clob_len <= 0;
    return 550015;
  endif;

  outData.r_clob  = %subst(ci_sql_clob_data:1:ci_sql_clob_len);

  outVersion.SrvcName = wSrvcNam;
  if GetHostSrvc(outVersion) <> 0;
    outData.r_pguid = 'Not Available';
    outData.r_aguid = inGuid;
    return 550017;
  endif;

  return 0;

end-proc;
