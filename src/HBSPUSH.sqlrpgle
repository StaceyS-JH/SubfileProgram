     H* DFTACTGRP(*NO) ACTGRP(*NEW) BNDDIR('HTTPAPI')
     H* DFTACTGRP(*NO) ACTGRP(*NEW)
       ctL-opt dftactgrp(*no) actgrp(*new);
       ctl-opt bnddir('HBSBIND':'JHBIND');
       ctl-opt option(*SrcStmt : *NoDebugIO);
       ctl-opt debug(*constants);
       ctl-opt main(Main);
       //ctl-opt bnddir('HTTPAPI');

26003 // 03/12/26 #1185227 M Collins - Add port to header when
26003 //                               encryption is off
26002 // 03/02/25 #1184581 S Smith - Resend logic changes
26001 // 11/05/25 #1184229 S Smith - BSL Subsystem Resiliency
24001 // 06/05/24 #1179375 V Everett - expand HBSSBSCTL
23002 // 09/05/23 S Smith #1177516 - psds from hbstools
23001 // 06/05/23 Greene   #1176052 - Start/end fi changes
sas    //

      /include qcpysrc,yajl_h
      /include qcpysrc,httpapi_h
23002 /define HBSTOOLS_psds
      /include qcpysrc,hbstools
23002 /undefine HBSTOOLS_psds


       //dcl-pi HBSPUSH;
       //  pDatq char(10) const;
       //  pGuid char(36) const options(*nopass);
       //end-pi;

23001D* CheckQue        pr            10i 0 opdesc
23001D*   p_dtaqnm                    10a   CONST
23001D* RcvDtaqKey      pr                  extpgm('QRCVDTAQ')
23001D*                               10a   const
23001D*                               10a   const
23001D*                                5  0
23001D*                               10a
23001D*                                5  0 const
23001D*                                2a   const
23001D*                                3  0 const
23001D*                               10a   const
23001D*                                3  0 const
23001D*                               10a   const
23001D*                               10a   Const
23001D*                                5  0 Const
23001D*                               10a   Const


       //---------------------------------------------------------------------
       // Data Structures
       //---------------------------------------------------------------------
       dcl-ds dsHBSSend;
         S_Pguid char(36) inz('');
         S_Aguid char(36) inz('');
         S_HostService char(10) inz('');
         S_Hdr varchar(1000) inz('');
         S_Attempts int(10) inz(0);
         S_Data sqltype(CLOB:2000000) inz('');
       end-ds;

       dcl-ds dsHbhsts;
         HS_ServerType char(3) inz('');
         HS_Header varchar(200) inz('');
         HS_SendRespService char(20) inz('');
       end-ds;

       dcl-ds dsHbspars qualified;
         num_Server_List int(10) inz;
         dcl-ds Server_list dim(10);
           Server_Type char(3) inz('');
       //    ConnectionType varchar(25) inz('');
           ConnectionTimeout int(10) inz(0);
           SocketTimeout int(10) inz(0);
           PushIdleTimeout int(10) inz(0);
           PersistentLoopWaitTime int(10) inz(0);
           UsePersistentConnection ind inz(*off);
           MaxAttempts int(10) inz(0);
           RetryDelay packed(5:2) inz(0.0);
           MaxConnectionAttempts int(10) inz(0);
           ConnectionRetryDelay packed(5:2) inz(0.0);
           UserAgent varchar(100) inz('');
           ContentType varchar(100) inz('');
           num_Server_IP_List int(10) inz;
           dcl-ds Server_IP_List dim(5);
             Name varchar(25) inz('');
             IP varchar(25) inz('');
             Port int(10) inz;
             Encryption ind inz(*off);
             App varchar(25) inz('');
           end-ds;
         end-ds;
         DebugHttp ind inz(*off);
         DebugFilePath varchar(200) inz('');
       end-ds;

       dcl-ds S_Info;
         sType char(3) inz('');
       //  ConType varchar(25) inz('');
         ConnectionTO int(10) inz(0);
         SocketTO int(10) inz(0);
         PushITO int(10) inz(0);
         PersistentWait int(10) inz(0);
         UsePersist ind inz(*off);
         MaxAttempts int(10) inz(0);
         RetryDelay packed(15:5) inz(0.0);
         MaxConAttempts int(10) inz(0);
         ConRetryDelay packed(15:5) inz(0.0);
         UserAgent varchar(100) inz('');
         ContType varchar(100) inz('');
       //  URL varchar(500) inz('');
       //  Debug ind inz(*off);
       //  DebugPath varchar(200) inz('');
         MultiIP ind inz(*off);
         IPCount int(10) inz(0);
         CurIPNum int(10) inz(0);
       end-ds;

       dcl-ds Servers likeds(S_Info) dim(10);

       dcl-ds IP_Info;
         Type char(3) inz('');
         Search varchar(25) inz('');
         Name varchar(25) inz('');
         URL varchar(500) inz('');
       end-ds;

       dcl-ds Server_Ips likeds(IP_Info) dim(10);

       dcl-ds myServer likeds(S_Info) inz;

       dcl-ds myIP likeds(IP_Info) inz;

       //dcl-ds Available_Servers dim(10) qualified;
       //  Search char(20) inz('');
       //  Number int(10) inz(0);
       //  Name varchar(25) inz('');
       //  ConnectionActive ind inz(*off);
       //  ServerResponding ind inz(*off);
       //  dcl-ds Info likeds(S_Info) inz;
       //end-ds;

       dcl-ds HostServices qualified dim(200);
         Name varchar(50) inz('');
         SvrType char(3) inz('');
         Header varchar(500) inz('');
         Response varchar(50);
       end-ds;

       dcl-ds RespHdrValues qualified dim(20);
         Name varchar(25) inz('');
         Value varchar(50) inz('');
       end-ds;

M03    dcl-ds HBSSBSCTL dtaara(*usrctl);
M03      d_SBSName char(10);
M03      d_SBSLib char(10);
M03      d_BankLib char(10);
M03      d_FINum char(4);
M03      d_LocalIP char(16);
24001    d_CoreID  char(5);
24001    d_Misc    char(445);
M03    end-ds;

       dcl-ds dsResponse qualified;
         Success ind inz(*off);
         dcl-ds BaseRequest;
           dcl-ds ActivityTracking;
             ActivityId char(36) inz('');
             ParentActivityId char(36) inz('');
           end-ds;
           RequestType varchar(100) inz('');
         end-ds;
       end-ds;

       dcl-ds *n extname('JHAPAR') dtaara (*auto) end-ds;

       //dcl-ds Pgm psds qualified;
       //  Proc char(10) ;             // Module or main procedure name
       //  StsCde zoned(5) ;           // Status code
       //  PrvStsCde zoned(5) ;        // Previous status
       //  SrcLineNbr char(8) ;        // Source line number
       //  Routine char(8) ;           // Name of the RPG routine
       //  Parms zoned(3) ;            // Number of parms passed to program
       //  ExceptionType char(3) ;     // Exception type
       //  ExceptionNbr char(4) ;      // Exception number
       //  Exception char(7) samepos(ExceptionType) ;
       //  Reserved1 char(4) ;         // Reserved
       //  MsgWrkArea char(30) ;       // Message work area
       //  PgmLib char(10) ;           // Program library
       //  ExceptionData char(80) ;    // Retrieved exception data
       //  Rnx9001Exception char(4) ;  // Id of exception that caused RNX9001
       //  LastFile1 char(10) ;        // Last file operation occurred on
       //  Unused1 char(6) ;           // Unused
       //  DteEntered char(8) ;        // Date entered system
       //  StrDteCentury zoned(2) ;    // Century of job started date
       //  LastFile2 char(8) ;         // Last file operation occurred on
       //  LastFileSts char(35) ;      // Last file used status information
       //  JobName char(10) ;          // Job name
       //  JobUser char(10) ;          // Job user
       //  JobNbr zoned(6) ;           // Job number
       //  StrDte zoned(6) ;           // Job started date
       //  PgmDte zoned(6) ;           // Date of program running
       //  PgmTime zoned(6) ;          // Time of program running
       //  CompileDte char(6) ;        // Date program was compiled
       //  CompileTime char(6) ;       // Time program was compiled
       //  CompilerLevel char(4) ;     // Level of compiler
       //  SrcFile char(10) ;          // Source file name
       //  SrcLib char(10) ;           // Source file library
       //  SrcMbr char(10) ;           // Source member name
       //  ProcPgm char(10) ;          // Program containing procedure
       //  ProcMod char(10) ;          // Module containing procedure
       //  SrcLineNbrBin bindec(2) ;   // Source line number as binary
       //  LastFileStsBin bindec(2) ;  // Source id matching positions 228-235
       //  User char(10) ;             // Current user
       //  ExtErrCode int(10) ;        // External error code
       //  IntoElements int(20) ;      // Elements set by XML-INTO or DATA-INTO (7.3)
       //  InternalJobId char(16) ;    // Internal job id (7.3 TR6)
       //  SysName char(8) ;           // System name (7.3 TR6)
       // end-ds ;

       //---------------------------------------------------------------------
       // Fields
       //---------------------------------------------------------------------
       dcl-s Abnormal_End ind inz(*off);
26001  dcl-s HttpErrorsOccuring ind inz(*on);
26001  dcl-s InvalidResponse ind inz(*off);
       dcl-s ResendsExist ind inz(*on);
       dcl-s rc int(10);
       dcl-s w_aguid char(36);

       dcl-s w_header varchar(1000);
       dcl-s w_qdata char(36);
sas    dcl-s rcv_qdata char(46);
sas    dcl-s rcv_datq char(10);
       dcl-s wDatQ char(10);
       dcl-s w_dtaqlib char(10);

       dcl-s w_sendq char(10);
       dcl-s w_wait packed(5);
       dcl-s wGuid char(36);
       dcl-s TestMode ind inz(*off);
       dcl-s Success ind inz(*off);

23001  dcl-s W_dtaqctl char(10);
23001  dcl-s W_dta30   char(10);
23001  dcl-s pushlog char(200);
23001  dcl-s gCntrlQ char(10);
       //
       dcl-s JsonMsg varchar(2000000);
       dcl-s SendResultStr varchar(2000000);

       dcl-s SendStr   varchar(2000000);
       dcl-s comm pointer inz(*null);
       dcl-s ConEndTime timestamp;
       dcl-s GuidFound ind;
       dcl-s fast_wait packed(5) inz(0);
       dcl-s PushIsActive ind;
       dcl-s ConnectionIsActive ind;
       dcl-s RequestSent ind;
       dcl-s SendAttempts int(3);
       dcl-s SendResultLen int(10) inz(0);

       dcl-s TestCounter int(10);

       dcl-s DebugActive ind inz(*off);

       dcl-s RequestCounter int(3) inz(0);
       dcl-s RequestAttempts int(3) inz(0);
       dcl-s ConCounter int(10) inz(0);
       dcl-s ConnectionAttempts int(3) inz(0);

       dcl-s Hdr_Connection varchar(50);
       dcl-s Hdr_ContentLength varchar(50);
       dcl-s Hdr_Date varchar(50);

26002  dcl-s CheckResend ind;
26002  dcl-s ResendQ char(10);
26002  dcl-s ResendCount int(10);
       //---------------------------------------------------------------------
       // Prototypes
       //---------------------------------------------------------------------
       //---------------------------------------------------------------------
       // Constants
       //---------------------------------------------------------------------
       //dcl-c cEndConn const('Connection: close');
       //dcl-c cHTTPOK const('HTTP/1.1 200 OK');
       dcl-c cSuccess const('"Success":true');
       dcl-c Yes const('1');
       dcl-c No const('0');
       dcl-c HttpAction 'POST';

       //---------------------------------------------------------------------
       // Main
       //---------------------------------------------------------------------
sas    //http_debug(*on: '/home/STACEYS/HBSPUSH_debug.txt');
       //https_strict(*ON);
       //
       //dcl-pi HBSPUSH;
       //  pDatq char(10) const;
       //  pGuid char(36) const options(*nopass);
       //end-pi;
       dcl-proc Main;
         dcl-pi *n extpgm('HBSPUSH');
           pDatq char(10) const;
           pGuid char(36) const options(*nopass);
         end-pi;

       dcl-s MainRC int(10) inz(0);

       Exec SQL
         Set Option
            commit = *none,
            CloSqlCsr = *endmod,
            Datfmt = *iso;

       if %parms < 2;
         wDatq = pDatq;
         wGuid = *blanks;
         TestMode = *off;
       else;
         wGuid = pGuid;
         wDatq = *blanks;
         TestMode = *on;
       endif;

       *inlr = *on;

M03    in HBSSBSCTL;
M03    w_dtaqlib = d_BankLib;

sas    //Check for return *off to see if an error occured during set up
       if (Setup() <> 0);
       // An error occured during SetUp - what should I do?
       endif;
       //LoadHostServices();

       // temp while testing
       *inlr = *on;

       // Do I need to make this a constant or parameter?
       w_wait = -1;
       PushIsActive = Yes;
       ResendsExist = Yes;

26002  CheckResend = No;

       Dow (PushIsActive);

       // If I'm going to check this for each loop - what if someone has turned
       // it on and hbspars by default has it turned off?  What would the push
       // control change to turn debug on or off dynamtically?  If HBSPARS
       // was refreshed it would grab the value from there.
       // I don't need to do this here.  When the service is processed then
       // I'll alter the values of DebugActive and issue the debug(*on) command
       // but only that one time.
       //////  if not(DebugActive);
       //////    if dsHbPars.DebugHttp;
       //////      hbstools_Actvty(S_Pguid:S_Aguid:560000:
       //////        'Debugging being written to ' + dsHbPars.DebugFilePath);
       //////      http_debug(*on: dsHbPars.DebugFilePath);
       //////      DebugActive = Yes;
       //////    else;
       //////      http_debug(*off);
       //////      DebugActive = No;
       //////    endif;
       //////  endif;

sas       //  ConCounter = 0;
         RequestCounter = 0;
          gCntrlQ = 'HBSCNTR' + %char(%editc(jhbnkn:'X'));

         clear w_qdata;
         GuidFound = *off;
         RcvDtaq(w_sendq:w_dtaqlib: %len(w_qdata): w_qdata: w_wait);

sas      if w_qdata = 'QUIT';
           http_persist_close(comm);
           reset comm;
           PushIsActive = No;
sas        leave;
sas      endif;

kkg    //  Control sending request to check control que
23001    if w_qdata = 'CONTROL';
23001       CheckQue(gCntrlQ);           // get control request for handler
26001       select;
26001       when w_dta30 = 'ENDJOB';
23001       // check if instructions to end job and log
26001       //23001       if w_dta30  = 'ENDJOB';
23001          clear Pushlog;
23001           Pushlog = 'Push Job#: ' +   Psjobnm +
23001                %char(psjob#) + 'Normal End';
23001          hbstools_Commlog(660001:pushlog);
23001          http_persist_close(comm);
23001        reset comm;
23001        PushIsActive = No;
23001        leave;
26001       when w_dta30 = 'RESEND';
26001          clear Pushlog;
26001         PushLog = 'Resending on Push Job: ' +
26001           psjobnm + %char(psjob#);
26001         hbstools_CommLog(560000:PushLog);
26001          w_qdata = *blanks;
26002          // Check the Resend Queue
26002          RcvDtaq(ResendQ
26002                 :w_dtaqlib
26002                 :%len(w_qdata)
26002                 :w_qdata
26002                 :0);
26002          if w_qdata <> *blanks;
26002            CheckResend = Yes;
26002          endif;
26002  //26001        LoadResend('R');
26002  //26001        LoadResend('H');
26001    //23001    else;
26001      other;
23001      W_qdata = *blanks;
23001      iter;
26001     endsl;
26001    //23001    endif;        // check endjob from control
23001    endif;        //check control req


         If w_qdata <> *blanks;
           w_Aguid = w_qdata;
         else;
           iter;
         endif;

         if GetData(w_Aguid) = *off;
           // GUID not found in send file
           hbstools_Commlog(45004: 'For ActivityId: ' + %trim(w_Aguid));
           // loop back and wait for another GUID
           iter;
         else;
           Guidfound = *on;
26002      SendAttempts = S_Attempts;
         endif;

         // Guid received
         hbstools_Actvty(S_Pguid:S_Aguid:550041);

         if S_HostService = 'PushCtrl';
           hbstools_Actvty(S_Pguid:S_Aguid:560000:'Push Control detected');
           PushControl();
           iter;
         endif;

         GetHostServiceData(S_HostService);

sas    // Need to verify that new entries get written with attempts set to zero
26002  //  SendAttempts = S_Attempts + 1;
         if ConnectTo(HS_ServerType);
           ConnectionIsActive = Yes;
         else;
           ConnectionIsActive = No;
sas    //  Write something to comlog and guid log?
sas    // Make sure the GUID has been flagged for Resend
           iter;
         endif;
sas    // What if ConnectTo fails?  Where does the program flow too?

       if ResendsExist;
26001  //  LoadResend();
26002  //26001  LoadResend('R');
         // All the R records should be added back to the datq now.
         ResendsExist = *off;
       endif;

sas      //  ConnectionIsActive = Yes;


sas    //   moved to ConnectTo
       //  ConEndTime = %timestamp() + %seconds(myServer.PushITO);

         //   Now we go into a faster loop to continue to send until our timeout.
         // We will do this for only one loop if persistence is not turned on
         dow (ConnectionIsActive);

           if %timestamp() > ConEndTime;
             // this will close the current connection due to no guid's to send
             // in the time span
sas9    //  Do I need to check for an active GUID here?
sas9    //  Is there a chance of loosing one?
             ConnectionIsActive = No;
sas9   //   If there is a guid I need to process it before I exit the loop
             iter;
           endif;

           if GuidFound;

           w_header = %trim(S_Hdr);

           http_xproc( HTTP_POINT_ADDL_HEADER : %paddr(CustomHeaders) );

           clear JsonMsg;

           JsonMsg = %trim(s_Data_data);

sas    //  Do I need JsonMsg or can I just use SendStr?
           SendStr = %trim(JsonMsg);
       //    SendLen = %len(SendStr);

           RequestSent = No;
26001  //    SendAttempts = 1;

           TestCounter += 1;

           SendResultStr = '';

           dow (not(RequestSent) and SendAttempts <= myServer.MaxAttempts);

26002        SendAttempts += 1;
             rc = http_persist_req( HttpAction
                                  : comm
                                  : %trim(myIP.URL) + %trim(w_header)
                                  : 0
                                  : *null
                                  : %addr(SendStr:*data)
                                  : %len(SendStr)
                                  : 0
                                  : %paddr(SaveToString)
                                  : myServer.SocketTO
                                  : myServer.UserAgent
                                  : myServer.ContType);

             Hdr_Connection = %trim(http_header('Connection'));
             Hdr_ContentLength = %trim(http_header('Content-Length'));
             Hdr_Date = %trim(http_header('Date'));

             hbstools_Actvty(S_Pguid:S_Aguid:560000: 'Response - Connection: ' +
                  Hdr_Connection + ', Content Length: ' +
                  Hdr_ContentLength);

             if Hdr_Connection = 'close';
               ConnectionIsActive = No;
               // This will allow the curent request to complete but then start
               // a new connection when another guid is added to the datq.
             endif;

             SendResultLen = %len(SendResultStr);

             UpdStat(S_Pguid:S_Aguid:'S':'Attempt ' + %char(SendAttempts) +
               ', RC = ' + %char(rc) + ', SendLen = ' + %char(%len(SendStr)) +
               ' , RcvLen = ' + %char(SendResultLen));


             // If no response or response length zero - retry - counter++
             if rc <= 0 or SendResultLen = 0;
26002  //        SendAttempts += 1;
               // delay
               hbstools_Actvty(S_Pguid:S_Aguid:560000: 'Delaying ' +
                  %char(myServer.RetryDelay) + ' seconds');
               MyDelay(myServer.RetryDelay);

               reset ConEndTime;
               //reset ComCurrentTime;
               http_persist_close(comm);
               reset comm;
               if ConnectTo(HS_ServerType);
                 ConnectionIsActive = Yes;
               else;
                 ConnectionIsActive = No;
               endif;

             else;
               RequestSent = Yes;
             endif;
           enddo;

26001      if InvalidResponse = Yes;
26001        rc = 600;
26001        // reset InvalidResponse
26001        InvalidResponse = No;
26001      endif;

           if SendAttempts > myServer.MaxAttempts;
             SendAttempts = myServer.MaxAttempts;
           endif;

           if RequestSent = No;
             if SendResultLen = 0;
               UpdStat(S_Pguid:S_Aguid:'E':'Empty server response');
             else;
               UpdStat(S_Pguid:S_Aguid:'E':
                 'Too many attempts ' + SendResultStr);
             endif;
           elseif RequestSent = Yes and SendResultLen > 0;
              select;
                when rc = 1;
                  // check for success
                  Success = (CheckSuccess() = 0);
                  if Success;
                    UpdStat(S_Pguid:S_Aguid:'Y':SendResultStr);
26001               // We have a succssful send and response now
26001               //  check to see if there were any http errors to resend
26001               if HttpErrorsOccuring = Yes;
26002  //26001               LoadResend('H');
26001                 HttpErrorsOccuring = No;
26001               endif;
                     // Process Send Response
sas                  // Make this a function call?
                     if HS_SendRespService <> '*SUCCESS';
                       rcv_datq = 'HBS' + %char(%editc(jhbnkn:'X')) + 'RQ01';
                       rcv_qdata = S_Aguid + 'SR';
                       hbstools_Actvty(S_Pguid:S_Aguid:560000:
                         %trim(rcv_qdata) + ' sent to ' + %trim(rcv_datq));
                       hbstools_SendDtq(rcv_datq: w_dtaqlib
                             :%len(%trim(rcv_qdata)):rcv_qdata);
                     endif;
                  else;
                    UpdStat(S_Pguid:S_Aguid:'U':SendResultStr);
                  endif;
                when rc >=300 and rc<=399;
                  UpdStat(S_Pguid:S_Aguid:'H'
                    :'HTTP Error code ' + %char(rc) + ' '+ SendResultStr);
                when rc >=400 and rc<=499;
26002  //26001      SendAttempts += 1;
26002  //           UpdStat(S_Pguid:S_Aguid:'H'
26002             UpdStat(S_Pguid:S_Aguid:'4'
                    :'HTTP Error code ' + %char(rc) + ' '+ SendResultStr);
                when rc >=500 and rc<=599;
26002           // Add to RSQ
26002             hbstools_SendDtq(ResendQ
26002                             :w_dtaqlib
26002                             :%len(S_Aguid)
26002                             :S_AGuid);
                  UpdStat(S_Pguid:S_Aguid:'H'
                    :'HTTP Error code ' + %char(rc) + ' '+ SendResultStr);
                other;
                  UpdStat(S_Pguid:S_Aguid:'H'
                    :'HTTP Error code ' + %char(rc) + ' '+ SendResultStr);
              endsl;
           else;
             // catch all status
           endif;   // if request sent
         endif;    // if guid is found

sas9       // I need to check for connection: close
sas9       // what happenbs here if persist is on but I get the close?

        if not(myServer.UsePersist);
          ConnectionIsActive = No;
          iter;
        endif;

        if ConnectionIsActive = No;
          iter;
        endif;

       // Only use this section of UsePersistentConnection is *on

         // Check the DatQ for more data to be sent.
         clear w_qdata;
         // pause for 0.25 seconds - need to make this a parameter/variable
       //  usleep(250000);
       //  MyDelay(PersistentWait);
         // Receive GUID from data
         // change fast_wait to zero so I use usleep for a less than a second delay

26002  // If Http errors are currently occuring then don't check the resend queue
26002  // this might occur if the BSL server is down for maint responding with
26002  // a 503 error
26002    if HttpErrorsOccuring = Yes;
26002  //    CheckSend = Yes;
26002      CheckResend = No;
26002    endif;
26002
26002    if CheckResend = Yes;
26002      RcvDtaq(ResendQ
26002             :w_dtaqlib
26002             :%len(w_qdata)
26002             :w_qdata
26002             :myServer.PersistentWait);
26002      if w_qdata = *blanks;
26002        CheckResend = No;
26002      endif;
26002    else;
26002      // Check SendQ
26002      RcvDtaq(w_sendq
26002             :w_dtaqlib
26002             :%len(w_qdata)
26002             :w_qdata
26002             :myServer.PersistentWait);
26002      if HttpErrorsOccuring = No;
26002        // Get the ResendQ message count
26002        exec sql
26002          SELECT current_messages into :ResendCount
26002            FROM QSYS2.DATA_QUEUE_INFO
26002            WHERE DATA_QUEUE_LIBRARY = :w_dtaqlib
26002            AND DATA_QUEUE_NAME = :ResendQ;
26002        // If ResendQ has GUID's then the next time around process them
26002        if ResendCount > 0;
26002          CheckResend = Yes;
26002        else;
26002          CheckResend = No;
26002        endif;
26002      endif;
26002    endif;


         GuidFound = *off;

sas      if w_qdata = 'QUIT';
           ConnectionIsActive = No;
           PushIsActive = No;
           iter;
sas      endif;
23001       // check if instructions to end job and log
23001    if w_qdata = 'CONTROL';
23001       CheckQue(gCntrlQ);           // get control request for handler
26001       select;
26001       when w_dta30 = 'ENDJOB';
26001    //23001       if w_dta30  = 'ENDJOB';
23001          clear Pushlog;
23001           Pushlog = 'Push Job#: ' +   Psjobnm +
23001                %char(psjob#) + 'Normal End';
23001          hbstools_Commlog(660001:pushlog);
23001          ConnectionIsActive = No;
23001          PushIsActive = No;
23001        leave;
26001       when w_dta30 = 'RESEND';
26001         clear Pushlog;
26001         PushLog = 'Resending on Push Job: ' +
26001           psjobnm + %char(psjob#);
26001         hbstools_CommLog(560000:PushLog);
26001         w_qdata = *blanks;
26002          // Check the Resend Queue
26002          RcvDtaq(ResendQ
26002                 :w_dtaqlib
26002                 :%len(w_qdata)
26002                 :w_qdata
26002                 :0);
26002          if w_qdata <> *blanks;
26002            CheckResend = Yes;
26002          endif;
26002  //26001       LoadResend('R');
26002  //26001       LoadResend('H');
26001     //23001    else;
26001       other;
23001      W_qdata = *blanks;
23001      iter;
26001      endsl;
26001    //23001    endif;        // check endjob from control
23001    endif;        //check control req


kkg    //  Add code here to check control dataq  and
         If w_qdata <> *blanks;
         //  TestGuid = w_qdata;
           w_Aguid = w_qdata;
         else;
           iter;
         endif;

         if GetData(w_Aguid) = *off;
           // GUID not found in send file
           hbstools_Commlog(45004: 'For ActivityId: ' + %trim(w_Aguid));
           // loop back and wait for another GUID
           iter;
         else;
           GuidFound = *on;
26002      SendAttempts = S_Attempts;
       //    reset the Com end time
           ConEndTime = %timestamp() + %seconds(myServer.PushITO);
         endif;

       enddo; // fast checking loop - stays running until our timeout.

       // Our timeout occured - close the connection and go back to wait forever
       reset ConEndTime;
       //reset ComCurrentTime;
       http_persist_close(comm);
       reset comm;
       enddo;   // outer loop - wait forever - asleep

       on-exit Abnormal_End;
           if Abnormal_End;
       //      close *all;
kkg    //      is this equivalent to pcleanup -- add log here to hbscomlog abnormal end
kkg    //      not sure if equivalent - need to test this
kkg          hbstools_CommLog(600000:psjobnm + 'Push Job  Ending Abnormally');
           endif;

       end-proc;
       //---------------------------------------------------------------------
       // GetData - Get the request information for this GUID
       //---------------------------------------------------------------------
       dcl-proc GetData;
         dcl-pi *n ind;
           pGuid char(36);
         end-pi;

sasx     reset dsHBSSend;
sasx     S_Data_len = 0;

          // Locate GUID and make sure status is new or resend
26004      exec sql
26004        Select t.HTRQPGUID, t.HTGUID, t.HTPNAME,
26004               t.HTREQHDR,
26004               t.HTATTEMPTS,
26004               r.HRBODY
26004          into :dsHBSSend
26004          from HBSTRANS t
26004          join HBSREQ r on r.HRGUID = t.HTGUID
26004          where t.HTGUID = :pGuid
26004            and t.HTTYPE = 'OUT';

          if sqlstate = '02000';
            return *off;
          endif;

          if  CheckSQLstate(sqlstate) = 'C';
            MsgHdlr(MessageType : GetSQLCode(sqlcode): MessageFile ) ;
            return *off;
          endif ;

          return *on;

        end-proc;

       //---------------------------------------------------------------------
       // UpdStat
       //---------------------------------------------------------------------
        dcl-proc UpdStat;
          dcl-pi *n;
            p_pguid char(36) const;
            p_aguid char(36) const;
            p_stat char(1) const;
            p_respnse varchar(2000000) const options(*nopass);
          END-PI;

          dcl-s w_timestmp timestamp;
          dcl-s w_respnse sqltype(CLOB:2000000) inz('');
          dcl-c Quote '''';
          dcl-s ShortResponse varchar(100);

          w_timestmp = %timestamp();

          reset w_respnse;
          w_respnse_len = 0;

          if p_stat = 'S';
       //  sas   r_attmpt += 1;
       //  sas   r_attmpt += 1;
          ENDIF;

          // Log received payload if exists
          If %parms < 4;
            w_respnse = 'No Server Response';
          else;
            w_respnse_data = %trim(p_respnse);
            w_respnse_len=%len(%trim(p_respnse));
          ENDIF;

26004      exec sql
26004        update HBSTRANS
26004          set HTSNDSTS = :p_stat,
26004              HTATTEMPTS = :SendAttempts
26004          where HTGUID = :p_aguid;
26004      if %parms >= 4 and
26004         (p_stat = 'Y' or p_stat = 'U' or
26004          p_stat = 'H' or p_stat = '4');
26004        exec sql
26004          update HBRESP set HSBODY = :w_respnse
26004            where HSGUID = :p_aguid;
26004        if sqlstate = '02000';
26004          exec sql
26004            insert into HBRESP (HSGUID, HSBODY)
26004              values(:p_aguid, :w_respnse);
26004        endif;
26004      endif;
sas    // result2
sas    // result
sas    //3406
sas    //3455
sas    //45001     Error   Message Length is zero
sas    //45002     Error   Message Length Does Not Match Message Size
sas    //45003     Error   Error Sending GUID to client
sas    //45004     Error   GUID not found in HBSSEND
sas    //45005     Info    Connection with server could not be established
sas    //45006     Error   Response received with no activity ID
sas    //45007     Error   Response contained invalid JSON
sas    //45008     Info    Request from server to end connection
sas    //45009     Info    New connection to server established
sas    //550010    Error   Handler Receive Data Queue not found

sas    //550040    Info    Event created and GUID sent to Push process
sas    //550041    Info    GUID received into Push process
sas    //550042    Error   Socket error during Push process - GUID not sent
sas    //550043    Info    Push Process send complete for GUID
sas    //550044    Info    GUID successfully Pushed to server
sas    //550045    Error   Push process errored during send of GUID
sas    //550046    Error   No response from server set to resend
sas    //550047    Info    Push process encountered unknown status update
sas    //550048    Info    GUID sent to send data queue for resend after connection ended
sas    //550049    Info    GUID updated for resend due to no server response before shutdown
sas    //550050    Info    GUID added to data queue for resend during push startup
sas    //550051    Info    GUID request sent to server
sas    //550052    Info    Empty server response on send

sas    // new
sas    //550053    Error   GUID was Pushed to server but Success was false
sas    //550054    Info    GUID sent to send data queue for resend
sas    //550055    Info    GUID updated for resend
sas    //550056    Info    GUID reset after being loaded from resend
sas    //550057    Info    GUID status updated
sas    //560000    Info    GUID Log Entry:

       //    dsLog.AdditionalInfo(idx) = %scanrpl('"':Quote:p_MoreInfoAry(idx));
          ShortResponse =  %scanrpl('"':Quote:%subst(w_respnse_data:1:100));
          Select;
            when p_stat = 'Y';
              hbstools_Actvty(p_pguid:p_aguid:550044:ShortResponse);
       //          :%subst(w_respnse_data:1:100));
       // 550044    Info    GUID successfully Pushed to server

            when p_stat = 'E';
              hbstools_Actvty(p_pguid:p_aguid:550045:ShortResponse);
       //         :%subst(w_respnse_data:1:100));
       // 550045    Error   Push process errored during send of GUID

sas         when p_stat = 'H';
sas    // might need a new log description
              hbstools_Actvty(p_pguid:p_aguid:550045:ShortResponse);
26001         HttpErrorsOccuring = Yes;
       //         :%subst(w_respnse_data:1:100));
       // 550045    Error   Push process errored during send of GUID

            when p_stat = 'R';
sas    // this would be used for connection problems
              hbstools_Actvty(p_pguid:p_aguid:550046:ShortResponse);
       //         :%subst(w_respnse_data:1:100));
       // 550046    Error   No response from server set to resend

            when p_stat = 'S';
              hbstools_Actvty(p_pguid:p_aguid:550051:ShortResponse);
       //          :%subst(w_respnse_data:1:100));
       // 550051    Info    GUID request sent to server

            when p_stat = 'U';
              hbstools_Actvty(p_pguid:p_aguid:550053:ShortResponse);
       //         :%subst(w_respnse_data:1:100));
       // 550053    Error   GUID was Pushed to server but Success was false

sas         when p_stat = 'N';
sas    // might need a new log description
sas    // this would be used for connection problems
sas    // not sure if I will need this
              hbstools_Actvty(p_pguid:p_aguid:550056:ShortResponse);
       //         :%subst(w_respnse_data:1:100));
       // Info    GUID reset after being loaded from resend

26002       when p_stat = '4';
26002  // might need a new log description
26002         hbstools_Actvty(p_pguid:p_aguid:550045:ShortResponse);
26002  //       HttpErrorsOccuring = Yes;
26002  // 550045    Error   Push process errored during send of GUID

            other;
              hbstools_Actvty(p_pguid:p_aguid:550047);
       //       :%subst(w_respnse_data:1:100));
       // 550047    Info    Push process encountered unknown status update

          ENDSL;

          return;

        end-proc;

       //---------------------------------------------------------------------
       // Setup
       //---------------------------------------------------------------------
       dcl-proc SetUp;
         dcl-pi *n int(10) end-pi;

       dcl-s myRC int(10);

       myRC = 0;

       monitor;

         myRC = LoadPushParameters();

         if myRC = 0;
           myRC = LoadHostServices();
         endif;

       on-error;
         myRC = -1;
       endmon;

       return myRC;

       end-proc;

       //---------------------------------------------------------------------
       // Setup
       //---------------------------------------------------------------------
       dcl-proc LoadPushParameters;
         dcl-pi *n int(10) end-pi;

       dcl-s myRC int(10);
       dcl-s idx1 int(10);
       dcl-s idx2 int(10);
       dcl-s idxIP int(10);
       dcl-s myURL varchar(500);
       dcl-s myPort int(10);
       dcl-s myEncrypted ind;
       dcl-s myBankServer char(20);
       dcl-s myClob varchar(32000);

       //clear Available_Servers;
       myRC = 0;

       monitor;
         clear Servers;
         clear dsHbspars;

         //Get the server parameters from hbspars
         myBankServer =  'SERVER' + %char(%editc(jhbnkn:'X'));

         Exec SQL
           select hssbsparm into :myClob
           from hbspars
           where hssbsid = :myBankServer;

         data-into dsHbspars %DATA(myClob
                       : 'doc=string case=convert countprefix= num_ -
                       allowextra=yes allowmissing=yes trim=none')
                       %PARSER('YAJLINTO');

         idxIP = 1;

         for idx1 = 1 to dsHbspars.num_Server_List;
           Servers(idx1).sType =
             dsHbspars.Server_list(idx1).Server_Type;

           Servers(idx1).MaxAttempts =
             dsHbspars.Server_list(idx1).MaxAttempts;

           Servers(idx1).RetryDelay =
             dsHbspars.Server_list(idx1).RetryDelay;

           Servers(idx1).MaxConAttempts =
             dsHbspars.Server_list(idx1).MaxConnectionAttempts;

           Servers(idx1).ConRetryDelay =
             dsHbspars.Server_list(idx1).ConnectionRetryDelay;

           Servers(idx1).UsePersist =
             dsHbspars.Server_list(idx1).UsePersistentConnection;

           Servers(idx1).ConnectionTO =
             dsHbspars.Server_list(idx1).ConnectionTimeout;

           Servers(idx1).SocketTO =
             dsHbspars.Server_list(idx1).SocketTimeout;

           Servers(idx1).PushITO =
             dsHbspars.Server_list(idx1).PushIdleTimeout;

           Servers(idx1).PersistentWait =
             dsHbspars.Server_list(idx1).PersistentLoopWaitTime;

           Servers(idx1).UserAgent =
             dsHbspars.Server_list(idx1).UserAgent;

           Servers(idx1).ContType =
             dsHbspars.Server_list(idx1).ContentType;

           Servers(idx1).ConnectionTO =
             dsHbspars.Server_list(idx1).ConnectionTimeout;

           Servers(idx1).SocketTO =
             dsHbspars.Server_list(idx1).SocketTimeout;

           Servers(idx1).PushITO =
             dsHbspars.Server_list(idx1).PushIdleTimeout;

           Servers(idx1).UserAgent =
             dsHbspars.Server_list(idx1).UserAgent;

           Servers(idx1).ContType =
             dsHbspars.Server_list(idx1).ContentType;

           Servers(idx1).IPCount =
             dsHbspars.Server_list(idx1).num_Server_IP_List;

           Servers(idx1).CurIPNum = 1;

           Servers(idx1).MultiIP =
             (Servers(idx1).IPCount > 1);

           for idx2 = 1 to Servers(idx1).IPCount;
             Server_Ips(idxIp).Type = Servers(idx1).sType;
             Server_Ips(idxIp).Search =
                %trim(Server_Ips(idxIP).Type) + %char(idx2);
             Server_Ips(idxIP).Name =
               dsHbspars.Server_list(idx1).Server_IP_List(idx2).Name;

             myURL =
               dsHbspars.Server_list(idx1).Server_IP_List(idx2).Ip;
             myPort =
               dsHbspars.Server_list(idx1).Server_IP_List(idx2).Port;
             myEncrypted =
               dsHbspars.Server_list(idx1).Server_IP_List(idx2).Encryption;

             if myEncrypted;
               myURL = 'https://' + %trim(myURL) + ':' + %char(myPort);
             else;
26003          //myURL = 'http://' + %trim(myURL);
26003          myURL = 'http://' + %trim(myURL) + ':' + %char(myPort);
             endif;

             Server_Ips(idxIP).URL = myURL;

             idxIP += 1;

           endfor;

         endfor;

         if dsHbsPars.DebugHttp;
           hbstools_Actvty(S_Pguid:S_Aguid:560000:
             'Debugging being written to ' + dsHbsPars.DebugFilePath);
           http_debug(*on: dsHbsPars.DebugFilePath);
           DebugActive = Yes;
         else;
           http_debug(*off);
           DebugActive = No;
         endif;

         If not hbstools_ChkDtaq(w_dtaqlib:wDatq);
           If not hbstools_CrtDtaq(w_dtaqlib:wDatq:36);
             myRC = -2;
         //      hbstools_Commlog(550010);
           else;
             w_sendq = wDatq;
           ENDIF;
         else;
           w_sendq = wDatq;
         endif;

26002  ResendQ = 'HBS' + %char(%editc(jhbnkn:'X')) + 'RSQ1';
26002    If not hbstools_ChkDtaq(w_dtaqlib:ResendQ);
26002      If not hbstools_CrtDtaq(w_dtaqlib:ResendQ:36);
26002        myRC = -3;
26002      endif;
26002    endif;

       on-error;
         myRC = -1;
       endmon;

       return myRC;

       end-proc;

       //---------------------------------------------------------------------
       // CheckSuccess
       //---------------------------------------------------------------------
       dcl-proc CheckSuccess;
         dcl-pi *n int(10) end-pi;

       dcl-s myRC int(10);

       myRC = 0;

       monitor;
         reset dsResponse;
         data-into dsResponse %DATA(SendResultStr
                  : 'doc=string case=convert countprefix= num_ -
                  allowextra=yes allowmissing=yes trim=none')
                  %PARSER('YAJLINTO');
       on-error;
         myRC = -1;
       endmon;

       return myRC;

       end-proc;
       //---------------------------------------------------------------------
       // LoadResend
       //---------------------------------------------------------------------
sas3  //  Need to change this so that once a guid is added to the datq that the
sas3  //  status in the file is changed to N  or can I just leave the as R until a status change
sas3  //  This is taking all the R records and reloading them onto the datq
sas3  //  This should only happen after a connection has been established.
        dcl-proc LoadResend;
26001  //   dcl-pi *n end-pi;
26001     dcl-pi *n;
26001       p_Type char(1) const;
26001     end-pi;

          dcl-ds ReSendIDs dim(400) qualified;
            rspguid char(36);
            rsaguid char(36);
          END-DS;

          dcl-s BlockSize int(10) inz(%elem(ReSendIDs));
          dcl-s EndOfFile ind inz(*off);
          dcl-s FetchIndex int(10) inz(0);

          dcl-s rs_qdata char(36) inz('');

          // create cursor to grab only records marked for resend
26001  //   Exec SQL
26001  //     Declare ReSendCSR cursor for
26001  //     Select Hsparntid, Hsactvtid
26001  //        from HBSSEND
26001  //        where Hsstat = 'R'
26001  //        for fetch only;
26004     exec sql
26004       Declare ReSendCSR cursor for
26004       Select HTRQPGUID, HTGUID
26004          from HBSTRANS
26004          where HTSNDSTS = :p_Type
26004            and HTTYPE = 'OUT'
26004          for fetch only;

          Exec SQL
            Open ReSendCSR;

          Dou EndOfFile = *on;

            Exec SQL
              Fetch Next from ReSendCSR for :BlockSize rows into :ReSendIDs;

           if sqlstate = '02000';
             EndOfFile = *on;
             leave;
           endif;

            if  CheckSQLstate(sqlstate) = 'C';
              MsgHdlr(MessageType : GetSQLCode(sqlcode): MessageFile ) ;
              leave;
            endif ;

            // recalculate block size if necessary
            if SQLErrD(5) = 100;
              BlockSize = SQLErrD(3);
              EndOfFile = *on;
            endif;

            for FetchIndex = 1 to BlockSize;

              clear rs_qdata;

              hbstools_Actvty(ReSendIDs(FetchIndex).rspguid
                             :ReSendIDs(FetchIndex).rsaguid
26001  //                      :550054);
26001                        :550050);

              rs_qdata = ReSendIDs(FetchIndex).rsaguid;

              hbstools_SendDtq(w_sendq:w_dtaqlib:%len(rs_qdata):rs_qdata);

sas    // do I need to do this?  or can I just keep them at an R status?
sas    //       UpdStat(ResendIDs(FetchIndex).rspguid
       //              :ResendIDs(FetchIndex).rsaguid
       //              :'N');

            endfor;

          enddo;

          Exec SQL
            Close ReSendCSR;

          clear ResendIDs;

        end-proc;

       //---------------------------------------------------------------------
       // GetHostServiceData
       //---------------------------------------------------------------------
       dcl-proc GetHostServiceData;
         dcl-pi *n ind;
           pHostService char(10) const;
         end-pi;

         dcl-s idx int(10);

         clear dsHbhsts;

         idx = %lookup(pHostService: HostServices(*).Name);

         if idx <= 0;
           return *off;
         endif;

         if idx > 0;
           HS_ServerType = HostServices(idx).SvrType;
           HS_Header = HostServices(idx).Header;
           HS_SendRespService = HostServices(idx).Response;
           return *on;
         endif;


       //   // Locate GUID and make sure status is new or resend
       //  Exec SQL
       //    Select srvrtyp, header, sndrsps
       //     into :dsHbhsts
       //     from hbhsts
       //     where hstsrvc = :pHostService;
       //
       //   if sqlstate = '02000';
       //     return *off;
       //   endif;
       //
       //   if  CheckSQLstate(sqlstate) = 'C';
       //     MsgHdlr(MessageType : GetSQLCode(sqlcode): MessageFile ) ;
       //     return *off;
       //   endif ;
       //
       //   return *on;

        end-proc;

       //---------------------------------------------------------------------
       // LoadHostServiceData
       //---------------------------------------------------------------------
       dcl-proc LoadHostServices;
         dcl-pi *n int(10) end-pi;

       //  dcl-s LoadComplete ind;
         dcl-s myRC int(10);

       myRC = 0;

       monitor;

       //  LoadComplete = *off;

         clear HostServices;

         Exec SQL
           declare HostServicesCSR cursor
             for Select hstsrvc, srvrtyp, header, sndrsps
               from hbhsts;
       //        where version?

         Exec SQL
           Open HostServicesCSR;

         Exec SQL
           Fetch Next
           From HostServicesCsr for 200 rows
           Into :HostServices;

         if sqlstate = '02000' or
           SQLerrd(3) <= 0;
       //    LoadComplete = *off;
           myRC = -3;
         endif;

         if SQLerrd(3) > 0;
       //     gListIndx = SQLerrd(3);
       //    LoadComplete = *on;
           myRC = 0;
         else;
       //     gListIndx = 0;
       //    LoadComplete = *off;
           myRC = -2;
         endif;

         Exec SQL
           Close HostServicesCsr;
         myRC = 1;
       on-error;
         myRC = -1;
       endmon;

       if myRC = 0;
          hbstools_Commlog(560000
            :Procname + 'Host Services Loaded');
       endif;

       return myRC;

       end-proc;
       //---------------------------------------------------------------------
       // MyDelay
       //---------------------------------------------------------------------
       dcl-proc MyDelay;
         dcl-pi *n int(10);
           pSecondsDelay packed(15:5) const;
         end-pi;

       dcl-s myRC int(10);
       dcl-c Micro 1000000;

       dcl-s rc int(10) inz(0);
       dcl-s mySeconds uns(10);

       monitor;
         if pSecondsDelay < 1.0;
           //usleep
           mySeconds = pSecondsDelay*Micro;
           rc = usleep(mySeconds);
         else;
           mySeconds = pSecondsDelay;
           rc = sleep(mySeconds);
         endif;
       on-error;
         myRC = -1;
       endmon;

       return rc;

       end-proc;

       //---------------------------------------------------------------------
       // ConnectTo
       //---------------------------------------------------------------------
       dcl-proc ConnectTo;
         dcl-pi *n ind;
           pServerType char(3);
         end-pi;

       //dcl-s idx1 int(10);
       //dcl-s idx2 int(10);
       //dcl-s CurrentServer int(10);
       //dcl-s ServerIdx char(5) inz('');
         dcl-s MultiCounter int(10) inz(0);

         ConCounter = 1;
         MultiCounter = 1;
         // User ServerType and Current from Servers to build SearchServerName
         // and then pull in information from Available_Servers

         NextServerIP(pServerType);


       // Set myServer based on ServerType and CurrentServer from Servers
       ////  idx2 = %lookup(pServerType: Servers(*).ServerType);
       ////  CurrentServer = Servers(idx2).CurIPNum;
         //Now get Server information
       ////  ServerIdx = %trim(pServerType) + %char(CurrentServer);
       ////  idx1 = %lookup(ServerIdx:
       ////    Available_Servers(*).Search);
       ////
       ////  myServer = Available_Servers(idx1).Info;
       ////
       ////  hbstools_Actvty(S_Pguid:S_Aguid:560000:
       ////  myServer.Name + ' selected');
       ////

         // Determine what to do with the CurIPNum value
         // Is this fall back or round robin.
         // Fallback will always try the next server in line.
       ////  if myServer.MultiIP and myServer.ConType = 'RoundRobin';
       ////    Servers(idx2).CurIPNum += 1;
       ////    if Servers(idx2).CurIPNum >
       ////      Servers(idx2).IPCount;
       ////      Servers(idx2).CurIPNum = 1;
       ////    endif;
       ////  endif;

 sas   // every time I turn debugging on it will reset
       //  if myServer.Debug;
       //    hbstools_Actvty(S_Pguid:S_Aguid:560000:
       //      'Debugging being written to ' + myServer.DebugPath);
       //    http_debug(*on: myServer.DebugPath);
       //  else;
       //    http_debug(*off);
       //  endif;
       //  if dsHbsPars.DebugHttp;
       //    hbstools_Actvty(S_Pguid:S_Aguid:560000:
       //      'Debugging being written to ' + dsHbsPars.DebugFilePath);
       //    http_debug(*on: dsHbsPars.DebugFilePath);
       //  else;
       //    http_debug(*off);
       //  endif;
sas    //http_debug(*on: '/home/STACEYS/HBSPUSH_debug2.txt');

         dow comm = *null and ConCounter < myServer.MaxConAttempts;
             rc = https_init(*blanks);
       //    rc = https_init('BSL_APPID');
       //    rc = https_init('BAD_APPID');
       //    rc = https_init('JX_CLIENT_IADAPTER');
           comm = http_persist_open(myIP.URL
                                   :myServer.ConnectionTO);

sas    // I need an inner counter for MultiIP servers
       // only increment the ConCounter if I have tried all the IP's
       // in the MultiIP list.  I may not know
           if comm = *null;
       //      hbstools_Actvty(S_Pguid:S_Aguid:560000:
       //        myServer.Name + ' connection failure');
             hbstools_Actvty(S_Pguid:S_Aguid:560000:
               'Connection failure ' + myIP.Name + ' with ' +
               myIP.URL );

       //      if myServer.MultiIP;
       //        NextServerIP(pServerType);
       //        hbstools_Actvty(S_Pguid:S_Aguid:560000:
       //          myServer.Name + ' selected');
       //        MultiCounter += 1;
       //      endif;

             if myServer.MultiIP and MultiCounter >= myServer.IPCount;
               myDelay(myServer.ConRetryDelay);
               ConCounter += 1;
               MultiCounter = 1;
               NextServerIP(pServerType);
sas    //        hbstools_Actvty(S_Pguid:S_Aguid:560000:
sas    //          myServer.Name + ' selected');
             elseif (myServer.MultiIP and MultiCounter < myServer.IPCount);
               NextServerIP(pServerType);
sas    //        hbstools_Actvty(S_Pguid:S_Aguid:560000:
sas    //          myServer.Name + ' selected');
               MultiCounter += 1;
             endif;

             if not(myServer.MultiIP);
               myDelay(myServer.ConRetryDelay);
               ConCounter += 1;
             endif;
           endif;

         enddo;

         if comm = *null;
       //
           hbstools_Commlog(45005: 'after max connection attempts');
       // This still counts as a Request Attempt
       //    RequestCounter += 1;
26002  // Add to Resend Queue
26002             hbstools_SendDtq(ResendQ
26002                             :w_dtaqlib
26002                             :%len(S_Aguid)
26002                             :S_AGuid);
           UpdStat(S_Pguid:S_Aguid:'R':
                   'No Response received from server');
           ResendsExist = *on;
           http_persist_close(comm);
           ConCounter = 0;
           return *off;
       //    iter;
         endif;

       // Connection is established
       // ConnectionActive = Y;
         hbstools_Actvty(S_Pguid:S_Aguid:560000:
         'Connected to ' + myIP.Name + ' with ' +
         myIP.URL );

sas      //  Connection End Time
         ConEndTime = %timestamp() + %seconds(myServer.PushITO);

          return *on;

        end-proc;

       //---------------------------------------------------------------------
       // SaveToString
       //---------------------------------------------------------------------
        dcl-proc SaveToString;
          dcl-pi *n int(10);
            fd   int(10) value;
            data char(2000000) options(*varsize) ccsid(*utf8);
            len  int(10) value;
          end-pi;

26001     dcl-s Test1 char(1);
26001     dcl-s Test2 int(10) inz(0);
26001     dcl-s Test3 int(10) inz(1);
26001     dcl-s Test4 int(10) inz(0);
26001     Test1 = 'N';

          if len > 0;
26001     monitor;
26001     if Test1 = 'Y';
26001       Test2 = Test3 / Test4;
26001     endif;
          SendResultStr += %subst(data:1:len);
26001     on-error;
26001       SendResultStr = 'Invalid Response String';
26001       InvalidResponse = Yes;
26001     endmon;
          endif;

          return len;
        end-proc;


       //---------------------------------------------------------------------
       // CustomHeaders
       //---------------------------------------------------------------------
        dcl-proc CustomHeaders;
          dcl-pi *n;
            Header varchar(1024);
            UserData pointer value;
          end-pi;

          Header = 'Connection: Keep-Alive ' + x'0d25';

        end-proc;

       //---------------------------------------------------------------------
       // NextServerIP
       //---------------------------------------------------------------------
       dcl-proc NextServerIP;
         dcl-pi *n int(10);
           pServerType char(3) const;
         end-pi;

         dcl-s rc int(10) inz(0);
         dcl-s idx1 int(10);
         dcl-s idx2 int(10);
         dcl-s CurrentServer int(10);
         dcl-s IpSearch char(5) inz('');
         dcl-s TestName varchar(25);

         idx1 = %lookup(pServerType: Servers(*).sType);
       ////  CurrentServer = Servers(idx1).CurIPNum;
         //Now get Server information
       ////  ServerIdx = %trim(pServerType) + %char(CurrentServer);
       ////  idx1 = %lookup(ServerIdx:
       ////    Available_Servers(*).Search);

         if Servers(idx1).MultiIP;
           Servers(idx1).CurIPNum += 1;
           if Servers(idx1).CurIPNum > Servers(idx1).IPCount;
             Servers(idx1).CurIPNum = 1;
           endif;
         endif;
         myServer = Servers(idx1);

         IpSearch = %trim(pServerType) + %char(myServer.CurIPNum);

         idx2 = %lookup(IpSearch: Server_Ips(*).Search);

         myIp = Server_Ips(idx2);

         hbstools_Actvty(S_Pguid:S_Aguid:560000:
         myIp.Name + ' selected');

       ////  // Determine what to do with the CurIPNum value
       ////  // Is this fall back or round robin.
       ////  // Fallback will always try the next server in line.
       ////  if myServer.MultiIP and myServer.ConType = 'RoundRobin';
       ////    Servers(idx2).CurIPNum += 1;
       ////    if Servers(idx2).CurIPNum >
       ////      Servers(idx2).IPCount;
       ////      Servers(idx2).CurIPNum = 1;
       ////    endif;
       ////  endif;
         return rc;

        end-proc;

       //---------------------------------------------------------------------
       // SaveToString
       //---------------------------------------------------------------------
       dcl-proc PushControl;
         dcl-pi *n int(10);
         end-pi;

         dcl-ds dsPushCtrl qualified;
           Institution int(10) inz(0);
           BankNo int(10) inz(0);
           Service varchar(25) inz('');
           Target varchar(25) inz('');
           TargetValue varchar(25) inz('');
         end-ds;
         dcl-s YajlOptions varchar(200);

         YajlOptions = 'doc=string case=convert';
         YajlOptions += ' allowextra=yes allowmissing=yes trim=none';

         clear JsonMsg;
         JsonMsg = %trim(s_Data_data);

         data-into dsPushCtrl %DATA(JsonMsg: YajlOptions)
           %PARSER('YAJLINTO');

         select;
           when dsPushCtrl.Service = 'SetValue';
             select;
               when dsPushCtrl.Target = 'DebugHttp';
                 select;
                   when dsPushCtrl.TargetValue = 'On';
                     if not(DebugActive);
                       http_debug(*on: dsHbsPars.DebugFilePath);
                       DebugActive = Yes;
                       hbstools_Commlog(560000
                       : 'HTTP Debugging turned on');
                     endif;
                   when dsPushCtrl.TargetValue = 'Off';
                     http_debug(*off);
                     DebugActive = No;
                 endsl;
             endsl;
           when dsPushCtrl.Service = 'Refresh';
         endsl;

         return 0;
       end-proc;
23001
23001 *--------------------------------------------------------\
23001 *  Check Controller queu and react to requests           |
23001 *--------------------------------------------------------/
26001P*23001 CheckQue        b
26001 *23001 CheckQue         pi            10i 0
26001D*23001   p_dtaqnm                    10a   const
26001 *23001
26001D*23001 ck_datqnm       s             10a   inz(*blanks)
26001D*23001 ck_datlib       s             10a   inz(*blanks)
26001D*23001 w_len           s              5  0 inz(10)
26001D*23001 w_wait          s              5  0 inz(0)
26001D*23001 w_keyord        s              2a   inz('NE')
26001D*23001 w_keylen        s              3  0 inz(10)
26001D*23001 w_keydata       s             10a   inz(*blanks)
26001D*23001 w_sendlen       s              3  0 inz(8)
26001D*23001 w_sendinf       s              8a   inz(*blanks)
26001D*23001 DataQLen        s              5  0 Inz(40)
26001D*23001 Qdlen           s              5  0
26001 *23001
26001D*23001 w_ErrDS         ds
26001D*23001   w_prvbyte             1      4i 0
26001D*23001   w_aftbyte             5      8i 0
26001D*23001   w_excpID              9     15
26001D*23001   w_reserv             16     16
26001  dcl-proc CheckQue;
26001    dcl-pi *n int(10);
26001      p_dtaqnm char(10) const;
26001    end-pi;
26001
26001  exec sql
26001  SELECT message_data
26001    into :w_dta30
26001    FROM TABLE(QSYS2.RECEIVE_DATA_QUEUE(
26001      DATA_QUEUE => :p_dtaqnm,
26001      DATA_QUEUE_LIBRARY => '*LIBL',
26001      REMOVE => 'NO',
26001      WAIT_TIME => 0,
26001      KEY_DATA => :psjobnm,
26001      KEY_ORDER => 'EQ'));
26001
);

26001  //    /free
          // change to recieve only entries for B###C job matching the controljob
          // dataq entry should be deleted when received
        // monitor;
26001  //   w_dta30  = *blanks;
26001  //   ck_datqnm = p_dtaqnm;
26001  //   ck_datlib = W_dtaqlib;
23001      //  RcvDtaq(ck_dtaqnm:w_dtaqlib: qdlen: w_dta: 0);
23001
26001  //23001   qdlen = %len(W_dta30);
26001  //23001   RcvDtaqKey(ck_datqnm:ck_datlib:qdlen:w_dta30: 0
26001  //23001                  : 'EQ' : 10 : psjobnm : 0 :*Blanks
26001  //             : '*NO' : DataqLen : w_ErrDS) ;




26001  //   23001   return rc;
26001    return 0;
         end-proc;
26001  //  23001 /end-free
26001P*23001 CheckQue        e
23001

       // 