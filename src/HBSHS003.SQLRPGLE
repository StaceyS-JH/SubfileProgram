       ctl-opt main(Main);
       ctl-opt option(*srcstmt : *nodebugio) bnddir('JHIGNM' : 'JHBIND');
       ctl-opt dftactgrp(*NO) actgrp(*CALLER);
       ctl-opt bnddir('HBSBIND') DECEDIT('0.');

26001  //11/05/25 #1184231 S Smith - Include Push status
24003  //                  S Smith - Include EOD and HBEOY data area information
24002  //01/02/24 #1181370 S Smith - Include Sysinfo data
24001 // 04/23/23 #        V Everett - expand HBSSBSCTL
23003  // 09/15/23 #1177741 S Smith - CL calling program changes
23002  // 09/05/23 #1177516 S Smith = psds from hbstools
23001  // 08/14/23 #1177830 S Smith - changes to CrtLogEvent parameters
23000  // 06/21/23 #1176933 S Smith - Subsystem Health Check - defaults to ping

       //--------------------------------------------------------------------
       //   Copyright 1988-2023 by:  Jack Henry & Associates, Inc. //
       //                      Jack Henry & Associates, inc.                -
       //                      Monett, Missouri  65708                      -
       //--------------------------------------------------------------------
       // Create command
      *> CRTSQLRPGI OBJ(&O/&ON) SRCFILE(&L/QRPGLESRC) -
      *> OBJTYPE(*PGM) OUTPUT(*NONE) RPGPPOPT(*LVL2) DBGVIEW(*SOURCE)

26001  dcl-pr SubmitSBSCommand extpgm('HBSSBMCMD');
26001    p_Function char(10) const;
26001  end-pr;

       dcl-ds dsJSONPackage qualified template;
         PGUID char(36) inz('');
         AGUID char(36) inz('');
         clob varchar(2000000) inz('');
       end-ds;

       dcl-ds dsResponse likeds(dsJSONPackage);

       dcl-ds dsReqJSON qualified;
         // define Standard fields
         /define StandardFields
         /include qcpysrc,hbsstand
         /undefine StandardFields
       end-ds;

       dcl-ds dsResJSON qualified;
         Success ind inz('0');
         num_ResponseDetailCollection int(10) inz(0);
         dcl-ds ResponseDetailCollection dim(20);
           ResponseCode int(10) inz(0);
           ResponseMessage varchar(200) inz('');
         end-ds;
24002    dcl-ds SystemInfo;
24002      Average_CPU_Rate packed(5:2);
24002      Average_CPU_Utilization packed(5:2);
24002      Minimum_CPU_Utilization packed(5:2);
24002      Maximum_CPU_Utilization packed(5:2);
24003      EODRunning ind inz('0');
24003      HBEOYRunning ind inz('0');
24002    end-ds;
26001    PushJobError ind inz(*off);
26001    num_PushJobs int(10) inz(0);
26001    dcl-ds PushJobs dim(10);
26001      Active ind inz(*off);
26001      ShortJobName char(10) inz('');
26001      Status char(10) inz('');
26001    end-ds;
26001    num_SendQueueCount int(10) inz(0);
26001    SendQueueCount int(10) inz(0);
26001    SendQueueWarning ind inz(*off);
         dcl-ds BaseRequest likeds(dsReqJSON);
       end-ds;

       dcl-s Error ind inz(*off);

       dcl-ds HBSSBSCTL dtaara(*usrctl);
         d_SBSName char(10);
         d_SBSLib char(10);
         d_BankLib char(10);
         d_FINum char(4);
         d_LocalIP char(16);
24001    d_CoreID  char(5);
24001    d_Misc    char(445);
       end-ds;

23003  dcl-s myService char(40) inz('');
24002  dcl-s Average_CPU_Rate packed(5:2) inz(0.0);
24002  dcl-s Average_CPU_Utilization packed(5:2) inz(0.0);
24002  dcl-s Minimum_CPU_Utilization packed(5:2) inz(0.0);
24002  dcl-s Maximum_CPU_Utilization packed(5:2) inz(0.0);
24003  dcl-s JHEOD char(10);
24003  dcl-s HBEOY char(10);

26001  dcl-ds JobListing dim(*auto: 99) qualified;
26001    Job_Name_Short char(10);
26001    Job_Status char(10);
26001    Subsystem char(10);
26001    Subsystem_Library_Name char(10);
26001    Function char(10);
26001  end-ds;
26001  dcl-s SendQueueCount int(10);
26001  dcl-s SendQueueWarning ind;
26001  dcl-s SendQueueName char(10);
26001  dcl-s PushJobName char(10);
26001  dcl-s PushJobCount int(10);
26001  dcl-s idx1 int(10);
26001  dcl-c SendQueueThreshold 50000;

        dcl-ds *n extname('JHAPAR') dtaara (*auto) end-ds;

       /define CrtLogEvent_prototype
       /include qcpysrc,hbssrv
       /undefine CrtLogEvent_prototype

23002  /define HBSTOOLS_psds
       /include qcpysrc,hbstools
23002  /undefine HBSTOOLS_psds

       dcl-proc Main;
         dcl-pi *N extpgm('HBSHS003');
           inPtr  pointer;
           outPtr pointer;
           Service char(40);
           Version char(40);
23003      RtnOpts char(40);
         end-pi;

         dcl-ds dsRequest likeds(dsJSONPackage) based(inPtr);

       exec sql set option dynusrprf = *owner,
             commit = *none,
             usrPrf = *user,
             datfmt    = *iso;

       dsResponse.PGUID = dsRequest.PGUID;
       dsResponse.AGUID = dsRequest.AGUID;

       in HbsSbsCtl;

       //myCounter+=1;

       ParseJSON(dsRequest.clob);

       dsResJSON.num_ResponseDetailCollection = 0;
       Error = *off;

       reset dsResJSON;

       //MoreInfoInit();
23003  clear RtnOpts;

23003  if Service = *blanks;
23003    myService = 'SubsystemHealthCheck';
23003  else;
23003    myService = Service;
23003  endif;
       // Validation

       if dsReqJSON.InstitutionId <> '';
         if dsReqJSON.InstitutionId <> d_FiNum;
           AddError(1000: 'Invalid Institution ID');
         endif;
       endif;
24002
24002  exec sql
24002    SELECT AVERAGE_CPU_RATE,
24002           AVERAGE_CPU_UTILIZATION,
24002           MINIMUM_CPU_UTILIZATION,
24002           MAXIMUM_CPU_UTILIZATION
24002           into
24002           :Average_CPU_Rate,
24002           :Average_CPU_Utilization,
24002           :Minimum_CPU_Utilization,
24002           :Maximum_CPU_Utilization
24002
24002      FROM TABLE(QSYS2.SYSTEM_ACTIVITY_INFO());
24002
24002  dsResJson.SystemInfo.Average_CPU_Rate = Average_CPU_Rate;
24002  dsResJson.SystemInfo.Average_CPU_Utilization = Average_CPU_Utilization;
24002  dsResJson.SystemInfo.Minimum_CPU_Utilization = Minimum_CPU_Utilization;
24002  dsResJson.SystemInfo.Maximum_CPU_Utilization = Maximum_CPU_Utilization;

24003  JHEOD = GetDataArea('JHEOD':'*LIBL');
24003  if JHEOD = 'READY';
24003    dsResJson.SystemInfo.EODRunning = *off;
24003  else;
24003    dsResJson.SystemInfo.EODRunning = *on;
24003  endif;
24003  HBEOY = GetDataArea('HBEOY':'*LIBL');
24003  if HBEOY = *blanks;
24003    dsResJson.SystemInfo.HBEOYRunning = *off;
24003  else;
24003    dsResJson.SystemInfo.HBEOYRunning = *on;
24003  endif;


26001  // Push Job Monitor
26001  PushJobName = 'B' + %char(%editc(jhbnkn:'X')) + 'P%';
26001  exec sql
26001    declare JobListCsr cursor for
26001      SELECT Job_Name_Short,
26001             Job_Status,
26001             Subsystem,
26001             Subsystem_Library_Name,
26001             Function
26001      FROM TABLE(QSYS2.ACTIVE_JOB_INFO
26001        ( subsystem_list_filter => :d_SBSName )) B
26001      WHERE JOB_name_short like trim(:PushJobName)
26001     ORDER BY JOB_NAME;
26001
26001  exec sql
26001    open JobListCsr;
26001
26001  exec sql
26001    fetch from JobListCsr for 99 rows
26001    into :JobListing;
26001
26001  PushJobCount = %elem(JobListing);
26001
26001  for idx1 = 1 to PushJobCount;
26001    dsResJson.PushJobs(idx1).Active = *on;
26001    dsResJson.PushJobs(idx1).ShortJobName =
26001      JobListing(idx1).Job_Name_Short;
26001    dsResJson.PushJobs(idx1).Status = JobListing(idx1).Job_Status;
26001  endfor;
26001
26001  dsResJson.num_PushJobs = PushJobCount;
26001
26001  if PushJobCount = 0;
26001    dsResJson.PushJobError = *on;
26001    SubmitSBSCommand('PUSH');
26001  else;
26001    dsResJson.PushJobError = *off;
26001  endif;
26001
26001
26001  exec sql
26001    close JobListCsr;
26001
26001  // Send Queue Monitor
26001  SendQueueName = 'HBS' + %char(%editc(jhbnkn:'X')) + 'SQ01';
26001  exec sql
26001    SELECT CURRENT_MESSAGES
26001      into :SendQueueCount
26001      FROM QSYS2.DATA_QUEUE_INFO
26001  WHERE DATA_QUEUE_LIBRARY = :d_BankLib AND
26001    DATA_QUEUE_NAME = :SendQueueName;
26001
26001  dsResJson.SendQueueCount = SendQueueCount;
26001  if SendQueueCount > SendQueueThreshold;
26001    dsResJson.SendQueueWarning = *on;
26001    dsResJson.num_SendQueueCount = 1;
26001  else;
26001    dsResJson.SendQueueWarning = *off;
26001    dsResJson.num_SendQueueCount = 1;
26001  endif;

       // Business Logic

       OutJSON();

       outPtr = %addr(dsResponse);

       //AddMoreInfo('Request');
       //AddMoreInfo(dsRequest.clob);
       //AddMoreInfo('Response');
       //AddMoreInfo(dsResponse.clob);



       //    swap the parent and activity ID
23001  //CrtLogEvent('INFO'
23001  //CrtLogEvent('LOGALWAYS'
23001  //       :dsRequest.AGUID
23001  //       :dsRequest.PGUID
23001  //         :dsRequest.PGUID
23001  //         :*omit
23001  //         :dsReqJSON.ActivityTracking.ParentActivityId
23001  //         :dsReqJSON.ActivityTracking.ActivityId
               //  :'RETAIL'
               //  : d_FiNum+'00000000'
               //  :*OMIT
23003  //       :'Host received SubsystemHealthCheck'
23003  //         :'Host received '+ %trim(myService)
               //  :MoreInfoAry
               //  :MoreInfoNum
         //  );
       end-proc;

      //---------------------------------------------------------
      // ParseJSON - Parse JSON string
      //---------------------------------------------------------
       dcl-proc ParseJSON;
         dcl-pi *n;
           pJSON varchar(2000000);
         END-PI;

       data-into dsReqJSON %DATA(pJSON
                       : 'doc=string case=convert countprefix= num_ -
                       allowextra=yes allowmissing=yes')
                              %PARSER('YAJLINTO');

       return;

       end-proc;

      //---------------------------------------------------------
      // OutJSON -
      //---------------------------------------------------------
       dcl-proc OutJSON;
         dcl-pi *n ind;
         end-pi;


       dsResJSON.BaseRequest = dsReqJSON;
       if Error;
         dsResJSON.success = *off;
       else;
         dsResJSON.success = *on;
       endif;

       %len(dsResponse.Clob) = 0;
       dsResponse.Clob = '';

       //  myJSON = dsResponse.Clob;
       DATA-GEN dsResJSON %DATA(dsResponse.Clob:
         'doc=string output=clear countprefix=num_')
         %GEN('YAJLDTAGEN');

       return *on;

       end-proc;


      //---------------------------------------------------------
      // AddError - add to the error array
      //---------------------------------------------------------
        dcl-proc AddError;
          dcl-pi *n ind;
            inErrorCode int(10) const;
            inErrorMessage varchar(200) const options(*nopass);
          end-pi;

        dcl-s myErrorCode int(10);
        dcl-s myErrorMessage char(200) inz;
        dcl-s ErrCount int(10);

        Error = *on;

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

        return *on;

        end-proc;

24003 //---------------------------------------------------------
24003 // Get Data Area
24003 //---------------------------------------------------------
24003  dcl-proc GetDataArea;
24003    dcl-pi *n char(1024);
24003      p_DataArea char(10) const;
24003      p_Library char(10) const;
24003    end-pi;
24003
24003  dcl-s DataString char(1024);
24003
24003  clear DataString;
24003
24003    exec sql
24003     SELECT DATA_AREA_VALUE into :DataString
24003       FROM TABLE(QSYS2.DATA_AREA_INFO(
24003            DATA_AREA_NAME => :p_DataArea,
24003            DATA_AREA_LIBRARY => :p_Library));
24003
24003   return DataString;
24003
24003  end-proc;


       /define CrtLogEvent_more
       /include qcpysrc,hbssrv
       /undefine CrtLogEvent_more
