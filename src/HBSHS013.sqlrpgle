       ctl-opt option(*srcstmt : *nodebugio) bnddir('JHIGNM' : 'JHBIND');
       ctl-opt dftactgrp(*NO) actgrp(*CALLER);
       ctl-opt bnddir('HBSBIND') DECEDIT('0.');

ssp22  // guid logs to hbslogf
ssp21  // Conditional logging
24000  // 09/10/24 #1180496 S Smith - New service to list entries in HBSVERSN
       //--------------------------------------------------------------------
       //   Copyright 1988-2024 by:  Jack Henry & Associates, Inc. //
       //                      Jack Henry & Associates, inc.                -
       //                      Monett, Missouri  65708                      -
       //--------------------------------------------------------------------
       //dcl-ds dsJSONPackage qualified template;
       //  PGUID char(36) inz('');
       //  AGUID char(36) inz('');
       //  clob varchar(2000000) inz('');
       //end-ds;

       dcl-s @RequestPtr  pointer;
       dcl-s @ResponsePtr pointer;
       //dcl-ds dsRequest likeds(dsJSONPackage) based(@RequestPtr);
       //dcl-ds dsResponse likeds(dsJSONPackage);
       dcl-ds dsRequest qualified based(@RequestPtr);
         Pguid char(36);
         AGuid char(36);
         clob varchar(32000);
       end-ds;
       dcl-ds dsResponse qualified;
         Pguid char(36);
         AGuid char(36);
         clob varchar(2000000);
       end-ds;

       dcl-ds dsReqJSON qualified;
         SortBy char(10) inz('');
         dcl-ds EndUser;
           InternalId varchar(25) inz('');
           InternalSecondaryId varchar(25) inz('');
           UserType int(10) inz(0);
         end-ds;
         // define Standard fields
         /define StandardFields
         /include qcpysrc,hbsstand
         /undefine StandardFields
       end-ds;

       dcl-ds dsResJSON qualified;
         Success ind inz('0');
sasx     CrtLogEvent ind inz('0');
sasx     AppErrLog ind inz('0');
         num_ResponseDetailCollection int(10) inz(0);
         dcl-ds ResponseDetailCollection dim(20);
           ResponseCode int(10) inz(0);
           ResponseMessage varchar(200) inz('');
         end-ds;
         RecordsAffected int(10) inz(0);
         num_ServiceList int(10) inz(0);
         dcl-ds ServiceList dim(500);
           Version char(40) inz('');
           ServiceName char(40) inz('');
           HostProgram char(10) inz('');
           Active ind inz('0');
           RunAsTest ind inz('0');
         end-ds;
         dcl-ds BaseRequest likeds(dsReqJSON);
       end-ds;

       dcl-ds dsHBSVersion dim(500) qualified;
         Version char(40);
         SrvcName char(40);
         HostSrvc char(10);
         Versnactv char(1);
         RunAsTest char(1);
       end-ds;
       dcl-s Error ind inz(*off);

       dcl-s AbnormalEnd ind inz(*off);
       dcl-s CrtLogType char(10) inz('');
       dcl-s ExceptionError ind inz(*off);
       dcl-s myActivityId char(36);
       dcl-s myPgm char(10);
       dcl-s myJobNbr char(10);
       dcl-s myJobName char(10);
       dcl-s myExceptionCode char(10);
       dcl-s PsdsString varchar(1000) inz('');
       dcl-s idx1 int(10) inz(0);
       dcl-s mySortBy char(10);
       dcl-s myCount int(10);

       //dcl-ds HBSSBSCTL dtaara(*usrctl);
       dcl-ds dsHBSSBSCTL;
         d_SBSName char(10);
         d_SBSLib char(10);
         d_BankLib char(10);
         d_FINum char(4);
         d_LocalIP char(16);
         d_CoreID  char(5);
         d_Misc    char(445);
       end-ds;

       dcl-ds *n extname('JHAPAR') dtaara (*auto) end-ds;

       /define CrtLogEvent_prototype
       /include qcpysrc,hbssrv
       /undefine CrtLogEvent_prototype

ssp22  /include qcpysrc,hbstools
       /include qcpysrc,hbspsds
       /include qcpysrc,jhdateucpy
       /copy qcpysrc,sqlstruct

       // Entry parms
       dcl-pi *N;
         @Req   pointer;
         @Res   pointer;
         Service char(40);
         Version char(40);
         RtnOpts char(40);
       end-pi;

       exec sql set option dynusrprf = *owner,
             commit = *none,
             usrPrf = *user,
             datfmt    = *iso;

         Main();
         return;

       dcl-proc Main;

       Initialize();

       @RequestPtr = @Req;
       @ResponsePtr = @Res;

       dsResponse.PGUID = dsRequest.PGUID;
       dsResponse.AGUID = dsRequest.AGUID;

ssp22  //hbstools_Actvty(dsRequest.PGUID:dsRequest.AGUID:560000:
ssp22  //     ' ' + %trim(myPSDS.Procname) + ' started');

       myActivityId = dsRequest.AGUID;
       myPgm = mypsds.ProcName;
       myJobNbr = %char(mypsds.JobNbr);
       myJobName = mypsds.JobName;

ssp22  // Insert a record into hbslogf
ssp22     hbstools_CrtLog(myActivityId
ssp22                     :'GUIDLOG'
ssp22                     :''
ssp22                     :'560000'
ssp22                     : %trim(myPSDS.Procname) + ' started'
ssp22                     :myPgm
ssp22                     :myJobName
ssp22                     :myJobNbr
ssp22                     :'Y');

       dsHBSSBSCTL = GetDataArea('HBSSBSCTL':'*LIBL');

sasx   if %subst(RtnOpts:1:1) = 'Y';
sasx     dsResJson.CrtLogEvent = *on;
sasx   else;
sasx     dsResJson.crtLogEvent = *off;
sasx   endif;
sasx   if %subst(RtnOpts:2:1) = 'Y';
sasx     dsResJson.AppErrLog = *on;
sasx   else;
sasx     dsResJson.AppErrLog = *off;
sasx   endif;

       MoreInfoInit();


 sas      //clear RtnOpts;

 sas      //reset dsResJSON;

       ParseJSON(dsRequest.clob);

       MoreInfoInit();

       if not(Error) and OpenFiles() = 0;
         if not(Error) and VldtInput() = 0;
           if not(Error) and SetDefaults () = 0;

       // Business Logic
       exec sql
         declare C0 cursor for
           select version, srvcname, hostsrvc, versnactv, runastest
           from hbsversn;

       exec sql
         open C0;

       exec sql
         fetch C0 for 500 rows into :dsHBSVersion;

       myCount = sqlerrd(3);

       select;
         when mySortBy = 'Service';
           sorta %subarr(dsHBSVersion:1:myCount)
             %fields(SrvcName);
         when mySortBy = 'Program';
           sorta %subarr(dsHBSVersion:1:myCount)
             %fields(HostSrvc);
       endsl;

       for idx1 = 1 to myCount;

       //  dsResJson.num_ServiceList += 1;
         dsResJson.ServiceList(idx1).Version = dsHBSVersion(idx1).Version;
         dsResJson.ServiceList(idx1).ServiceName =
           dsHBSVersion(idx1).SrvcName;
         dsResJson.ServiceList(idx1).HostProgram =
           dsHBSVersion(idx1).HostSrvc;
         if dsHBSVersion(idx1).Versnactv = 'Y';
           dsResJson.ServiceList(idx1).Active = *on;
         else;
           dsResJson.ServiceList(idx1).Active = *off;
         endif;
         if dsHBSVersion(idx1).RunAsTest = 'Y';
           dsResJson.ServiceList(idx1).RunAsTest = *on;
         else;
           dsResJson.ServiceList(idx1).RunAsTest = *off;
         endif;
       endfor;

       exec sql
         close C0;

       dsResJson.num_ServiceList = idx1 - 1;
       dsResJson.RecordsAffected = dsResJson.num_ServiceList;


           endif;  // SetDefaults
         endif;  // Validation check
       endif; // Open Files

       OutJSON();

       @Res = %addr(dsResponse);

       AddMoreInfo('Request');
       AddMoreInfo(dsRequest.clob);
       AddMoreInfo('Response');
       AddMoreInfo(dsResponse.clob);

       select;
         when Error = *on;
           if ExceptionError = *off;
             CrtLogType = 'ERROR';
           else;
             CrtLogType = 'CRITICAL';
           endif;
         when Error = *off;
           CrtLogType = 'LOGALWAYS';
       endsl;

       CrtLogEvent(CrtLogType
                :dsRequest.PGUID
                :*omit
                :dsReqJSON.ActivityTracking.ParentActivityId
                :dsReqJSON.ActivityTracking.ActivityId
                :'RETAIL'
                :dsReqJSON.EndUser.InternalID
                :dsReqJSON.EndUser.InternalSecondaryId
                :'Host received ' + %trim(Service)
                :MoreInfoAry
                :MoreInfoNum
         );

       on-exit AbnormalEnd;
       //  close *all;
         exec sql
           close C0;
         if AbnormalEnd;
       //    close *all;
           exec sql close C0;
         endif;

       end-proc;

      //---------------------------------------------------------
      // ParseJSON - Parse JSON string
      //---------------------------------------------------------
       dcl-proc ParseJSON;
         dcl-pi *n;
           pJSON varchar(32000);
         END-PI;

       dcl-s DataIntoOptions varchar(200);
       dcl-s YajlIntoOptions varchar(200);

       DataIntoOptions = 'doc=string case=convert countprefix= num_  -
         allowextra=yes allowmissing=yes';

       YajlIntoOptions = '{ "skip_null": true}';

         data-into dsReqJSON %DATA(pJSON
                         : DataIntoOptions)
                                %PARSER('YAJLINTO'
                                :YajlINtoOptions);

         return;

       end-proc;

      //---------------------------------------------------------
      // OutJSON -
      //---------------------------------------------------------
       dcl-proc OutJSON;
         dcl-pi *n ind;
         end-pi;

       dcl-s DataGenOptions varchar(200);

       DataGenOptions = 'doc=string output=clear countprefix=num_';

         dsResJSON.BaseRequest = dsReqJSON;

         if Error;
           dsResJSON.success = *off;
ssp23      hbstools_AddIdx(dsRequest.AGUID
ssp23                     :'SUCCESS'
ssp23                     :'FALSE');
         else;
           dsResJSON.success = *on;
ssp23      hbstools_AddIdx(dsRequest.AGUID
ssp23                     :'SUCCESS'
ssp23                     :'TRUE');
         endif;

         %len(dsResponse.Clob) = 0;
         dsResponse.Clob = '';

       //  myJSON = dsResponse.Clob;
         DATA-GEN dsResJSON %DATA(dsResponse.Clob:
           DataGenOptions)
           %GEN('YAJLDTAGEN');

         return *on;

       end-proc;

      //---------------------------------------------------------
      // Format PsdsString
      //---------------------------------------------------------
       dcl-proc FormatPsds;
         dcl-pi *n ind;
         end-pi;

         monitor;
         reset PsdsString;

       //  myJSON = dsResponse.Clob;
         DATA-GEN mypsds %DATA(PsdsString:
           'doc=string output=clear countprefix=num_')
           %GEN('YAJLDTAGEN');
         on-error;
           PsdsString = 'Error in FormatPsds procedure';
         endmon;
         return *on;

       end-proc;

      //---------------------------------------------------------
      // AddError - add to the error array
      //---------------------------------------------------------
        dcl-proc AddError;
          dcl-pi *n ind;
            inErrorType char(1) const;
            inErrorCode int(10) const;
            inErrorMessage varchar(200) const options(*nopass);
          end-pi;

          dcl-s myErrorCode int(10);
          dcl-s myErrorMessage char(200) inz;
          dcl-s ErrCount int(10);

          if inErrorType = 'E';
            Error = *on;
          endif;

          if %parms() >= %parmnum(inErrorMessage);
            myErrorMessage = inErrorMessage;
            myErrorCode = inErrorCode;
          endif;

          dsResJSON.num_ResponseDetailCollection += 1;
          ErrCount = dsResJSON.num_ResponseDetailCollection;
          dsResJSON.ResponseDetailCollection(ErrCount).ResponseCode
              = myErrorCode;

          dsResJSON.ResponseDetailCollection(ErrCount).ResponseMessage
              = %trim(myErrorMessage);

       // Insert a record into hbslogf
          hbstools_CrtLog(myActivityId
                          :'ERROR'
                          :'APP'
                          :%char(myErrorCode)
                          :myErrorMessage
                          :myPgm
                          :myJobName
                          :myJobNbr);

          return *on;

        end-proc;

      //---------------------------------------------------------
      // VldtInput
      //---------------------------------------------------------
       dcl-proc VldtInput;
         dcl-pi *n int(10) end-pi;

       monitor;

       mySortBy = dsReqJson.SortBy;

       on-error *all;
         AddError('E': 2000: 'Validation Error');
         return -1;
       endmon;

       return *zero;

       end-proc;

      //---------------------------------------------------------
      // SetDefaults
      //---------------------------------------------------------
       dcl-proc SetDefaults;
         dcl-pi *n int(10) end-pi;

       monitor;

       if mySortBy = *blanks;
         mySortBy = 'Service';
       endif;

       on-error *all;
         AddError('E': 2001: 'Set Defautls Error');
         return -1;
       endmon;

       return *zero;

       end-proc;

      //---------------------------------------------------------
      // Open Files
      //---------------------------------------------------------
       dcl-proc OpenFiles;
         dcl-pi *n int(10) end-pi;

       return *zero;

       end-proc;

       //---------------------------------------------------------
       // Initialize
       //---------------------------------------------------------
       dcl-proc Initialize;
         dcl-pi *n ind;
         end-pi;

       reset dsReqJSON;
       reset dsResJSON;
       Error = *off;
       clear dsHBSVersion;


       reset AbnormalEnd;
       reset CrtLogType;
       reset ExceptionError;
       reset myActivityId;
       reset myPgm;
       reset myJobNbr;
       reset myJobName;
       reset myExceptionCode;
       reset PsdsString;
       reset idx1;
       reset mySortBy;
       reset myCount;

       return *on;

       end-proc;

      //---------------------------------------------------------
      // Get Data Area
      //---------------------------------------------------------
       dcl-proc GetDataArea;
         dcl-pi *n char(1024);
           p_DataArea char(10) const;
           p_Library char(10) const;
         end-pi;

       dcl-s DataString char(1024);

       clear DataString;

         exec sql
          select data_area_value into :DataString
            from table(qsys2.data_area_info(
                 data_area_name => :p_DataArea,
                 data_area_library => :p_Library));

        return DataString;

       end-proc;

       /define CrtLogEvent_more
       /include qcpysrc,hbssrv
       /undefine CrtLogEvent_more 