       ctl-opt option(*srcstmt : *nodebugio);
       ctl-opt bnddir('JHIGNM':'JHBIND');
       ctl-opt bnddir('HBSBIND') DECEDIT('0.');
       ctl-opt dftactgrp(*NO);
       ctl-opt actgrp('BSL');

23006 // 04/15/24 S Smith  #1178700 - Valide FI Number in Request Headere
23005 // 09/18/23 S Smith  #1176604 - Large returns (GetAchBatchDetail)
23004 // 09/05/23 S Smith  #1177516 - psds changes
23003 // 06/05/23 Greene   #1176052 - Start/end fi changes
23002 // 05/11/23 Greene   #xxxxxxx - Fix for size of bigbuffer
23001 // 04/11/23 Greene   #xxxxxxx - Option to upgrade connection to SSL/TLS
M03   // 10/2/22 Everett - retrieve bank libs from HBSSBSCTL
      // 02/14/20 Greene   #xxxxxxx - Child Server Worker
      //                   #xxxxxxx - accept is on the parent job
      // BSL Rewrite - replaced HBSRECV/HBSSEND with HBSTRANS/HBSREQ/HBRESP
      // Create command
      *> CRTSQLRPGI OBJ(&O/&ON) SRCFILE(&L/QRPGLESRC) -
      *> OBJTYPE(*PGM) OUTPUT(*NONE) RPGPPOPT(*LVL2) DBGVIEW(*SOURCE)


     *****************************************************************
      *   Child Server Worker x
     *****************************************************************
      //       qcpysrc,hb_socket


23001   /define hbsgsk_Pr
23001   /include qcpysrc,hbsgskm
23001   /undefine hbsgsk_Pr


        /include qcpysrc,ibmtools

      /include qcpysrc,hbiconv
      /include qcpysrc,yajl_H
23004  /define HBSTOOLS_psds
      /include qcpysrc,hbstools
23004  /undefine HBSTOOLS_psds
       /define HBSSBSCTL
       /include qcpysrc,hbsstand
       /undefine HBSSBSCTL

         // execute iSeries system command
         //include qcpysrc,systemcpy


      *****************************************************************
      * Constants
      *****************************************************************

       dcl-s FiftyMilliseconds int(10) inz(50000);
       dcl-c AF_INET      2;
       dcl-c AF_UNIX      1;
       dcl-c INADD_NONE   -1;
       dcl-c INADDR_ANY   0;
       dcl-c REUSEADDR    55;
       dcl-c SCK_STREAM   1;
       dcl-c SOCK_DGRAM   2;
       dcl-c SOL_socket   -1;
       dcl-c TCP_NODELAY  10;
       dcl-c IPPROTO_IP   0;



      *****************************************************************
      * Data Structures
      *****************************************************************


       dcl-ds gIPlist dim(100) qualified;
         SrvrNum int(10);
         SrvrIP char(16);
         SrvrPort packed(5);
         Secure ind;
         SrvrApp char(100);
       END-DS;
       dcl-ds entry qualified;
         ChildId   char(10);
         Gsecurity char(1);
         Appid     char(50);
       end-ds;

       dcl-ds sockaddrin;
         familyin  int(5);
         portin    uns(5);
         addressin uns(10);
         zeroin    char(8);
       end-ds;

       dcl-ds msghdr;
         msg_name  pointer inz(*null);
         msg_namel int(10) inz(0);
         msg_iov   pointer inz(%addr(iovec));
         msg_iovl  int(10) inz(1);
         msg_accr  pointer inz(*null);
         msg_accrl int(10) inz(%size(sockaccept));
       end-ds;

       dcl-ds iovec;
         qdatainp pointer;
         qdatalen int(10) inz(257);
       end-ds;

       dcl-ds inherit;
         in_flags    uns(10) inz(0);
         in_pgroup   int(10) inz(0);
         in_sigmask1 uns(10) inz(0);
         in_sigmask2 uns(10) inz(0);
         in_sigdef1  uns(10) inz(0);
         in_sigdef2  uns(10) inz(0);
       end-ds;

      // Carriage Return Line Feed - Hex value of these two characters
       dcl-c CRLF const(x'0d25');
       dcl-c cEndr const('"HBServiceType":"ENDRECV"');


       // ReadDta: r_guid=HSGUID (= HTGUID = w_guid2), r_clob=HSBODY
       dcl-ds ReadDta;
         r_guid   char(36);
23005     r_clob sqltype(clob:2000000) inz('');
       END-DS;



      // Stand Alone Fields
       dcl-s w_dta30       char(10);
       dcl-s qcmd          char(512);
       dcl-s qcmdln        packed(15:5);
       dcl-s qdatain       char(5000);
       dcl-s qdata         char(5000);
       dcl-s sockaccept    int(10) inz(-1);
       dcl-s socklisten    int(10) inz(-1);
       dcl-s ChildSocketID int(10);
       dcl-s Index         int(5);
       dcl-s argv          char(1024);
       dcl-s Data          char(1024);
       dcl-s pbuffer       pointer;
       dcl-s pbuffersav    pointer inz(%addr(rcvbuff));
       dcl-s buffer        char(32000);
       dcl-s etoasize      packed(10);
       dcl-c @SecondaryFailed 'Secondary Receive Failed.';
       dcl-s F_SETFL       int(10) inz(7);
       dcl-s errWouldBlock int(10) inz(3406);
       dcl-s RetryCounter  int(5);
       dcl-s RecvRetry     int(5);
       dcl-s PartialRetry  int(5);
       dcl-s t_timestamp   timestamp;
       dcl-s flags         int(10) inz(0);
       dcl-s lensckadin    int(10) inz(%size(sockaddrin));
       dcl-s ReceiveError  ind inz(*off);
       dcl-s WaitTime      packed(5) inz(60);          // Seconds
       dcl-s w_dtaqnm      char(10) inz('HBS000RQ01');
       dcl-s w_dtaqctl     char(10) inz('HBSCNTR');
       dcl-s w_dtaqlib     char(10);
       dcl-s w_len         packed(5) inz(10);
       dcl-s w_wait        packed(5) inz(0);
       dcl-s totr          int(10) inz(0);
       dcl-s retry         packed(3) inz(0);
       dcl-s gSecurity     ind;
          dcl-s rcvbuffl   int(10);
          dcl-s w_end int(10);
          dcl-s w_starth int(10);
23003     dcl-s rc int(10);

       dcl-s totrecv  packed(9) inz(0);
       dcl-s totsend  packed(9) inz(0);
       dcl-s rcvLen int(10);
       dcl-s buffsent int(10);
23002  //dcl-s bigbuffer varchar(32767);
23sas  dcl-s bigbuffer varchar(2000000);
23sas  dcl-s bigbuffero varchar(2000000) ccsid(*utf8);
       dcl-s errmsg varchar(500);
       dcl-s bnkno  char(3);
       dcl-s end ind;
       dcl-s jsonerr ind;
       dcl-s h400err ind;
       dcl-s h500err ind;
sas    //dcl-s PrmJson varchar(2000);
sas    dcl-s PrmJson varchar(32000);
       dcl-s PrmHead varchar(2000);
       dcl-s PrmPtr pointer;
       dcl-s w_qlen packed(5) inz(46);
       dcl-s w_qdata char(46);
       dcl-s w_qlen2 packed(5) inz(36);
       dcl-s w_timestmp timestamp;
       dcl-s w_stat char(1);
       dcl-s w_sendq char(10);
23sas  //dcl-s SndBuff varchar(32000);
23sas  dcl-s SndBuff varchar(2000000);
       dcl-s w_guid char(36);
       dcl-s w_guid2 char(36);
       dcl-s w_pguid char(36);      // ParentActivityId parsed from JSON
       dcl-s totlrcv int(10);
       dcl-s jsonstrt int(10);
       dcl-s content_length int(10);
       dcl-s morereq int(10);

       //YAJL work fields
       dcl-s docnode like(yajl_val);
       dcl-s node like(yajl_val);
       dcl-s ActvtyTrck like(yajl_val);
       dcl-s bufferlen int(10);
       dcl-s iToGet int(10);
       dcl-s o_nonblock int(10) inz(128);
       dcl-s result int(10);
       dcl-s result2 int(10);
       dcl-s RCVBuff char(32768);
       dcl-s RcvStart   timestamp;
       dcl-s StartTime  timestamp;
       dcl-s EndTime  timestamp;
       dcl-s RCVStats char(200);
       dcl-s Recvstart char(50);
23001  dcl-c MsgEnd const(x'0d25F00d25');
23001     dcl-s w_start int(10);
23001     dcl-s w_buffer varchar(32768);

      // ----- Unsure of lines above ----
       dcl-s pcleanup pointer(*proc) inz(%paddr('CLEANUP'));



23001  /define HBSGSK_Proto
23001  /include qcpysrc,HBSGSKM
23001  /undefine HBSGSK_Proto

       // Check Controller queue - receives control command into w_dta30
       dcl-pr CheckKeyQue int(10);
         p_dtaqnm char(10) const;
         p_dtaqlib char(10) const;
         p_keydata char(10) const;
       end-pr;

       // Delete data queue for Worker Jobs.
       dcl-pr Dltdtaq;
         p_dtaqnm char(10) const;
       end-pr;

       // QCMDEXC to run commands.
       dcl-pr cmdexc extpgm('QCMDEXC');
         cmdtxt   like(qcmd);
         cmdlngth like(qcmdln);
       end-pr;

       // Prototype cleanup procedure.
       dcl-pr cleanup;
         Info pointer;
       end-pr;

       // Accept a connection. Returns CONNECTION's socket descriptor.
       dcl-pr accept int(10) extproc('accept');
         socketdesc int(10) value;
         sockaddrss pointer value;
         addresslen int(10);
       end-pr;

       // Receive data on socket. Returns -1 if error, else # of bytes recv'd.
       dcl-pr recv int(10) extproc('recv');
         socketdesc int(10) value;
         buffer     pointer value;
         bufferlen  int(10) value;
         flags      int(10) value;
       end-pr;

       // Close socket.
       dcl-pr close int(10) extproc('close');
         socketdesc int(10) value;
       end-pr;

       // The recvmsg function returns a -1 if unsuccessful.
       dcl-pr recvmsg int(10) extproc('recvmsg');
         socketdesc int(10) value;
         msghdr     pointer value;
         flags      int(10) value;
       end-pr;

       // The Send function returns a -1 if unsuccessful.
       // If successful, it returns the number of bytes sent.
       dcl-pr send int(10) extproc('send');
         socketdesc int(10) value;
         buffer     pointer value;
         bufferlen  int(10) value;
         flags      int(10) value;
       end-pr;

       // The SetSockOpt function returns a -1 if unsuccessful.
       dcl-pr setsockopt int(10) extproc('setsockopt');
         socketdesc int(10) value;
         level      int(10) value;
         optionname int(10) value;
         optionvalu pointer value;
         optionlen  int(10) value;
       end-pr;



       dcl-pr ChkDtaq ind;
         p_Dtaq char(10);
       end-pr;


       dcl-pr ChkDtaq2 ind;
         p_Dtaq char(10);
       end-pr;



       // The FCntl function returns a -1 if unsuccessful.
       dcl-pr fcntl int(10) extproc('fcntl');
         socketdesc int(10) value;
         F_SETFL    int(10) value;
         O_NONBLOCK int(10) value options(*nopass);
       end-pr;



       dcl-pr ReadSQL ind end-pr;

       dcl-pr UpdtStat;
         stat char(1) const;
       END-PR;


       dcl-pr UpdtStatR;
         stat char(1) const;
       END-PR;


       dcl-pr CheckHeader int(10);
         i_buffer char(32768) const;
         w_starth int(10)  value;
       END-PR;


       dcl-pr BldHeader varchar(2000);
         srvc char(40) value;
       END-PR;

       dcl-pr GetErr char(200);
         enum int(10) value;
       END-PR;

       dcl-pr ErrLog;
         errnum int(10) value;
       END-PR;

       dcl-pr ErrHandlr extproc('CEEHDLR');
         ProcPtr pointer(*proc) const;
         ProcName char(10) const;
         Omit char(12) options(*omit);
       END-PR;

       dcl-pr Errcheck int(10);
         result int(10);
       END-PR;


       dcl-pr ParseJson end-pr;
       dcl-pr RecvDta ind end-pr;
       dcl-pr SendDta ind end-pr;
       dcl-pr SendDtaerr ind end-pr;
       dcl-pr WriteRecv ind end-pr;
       dcl-pr WriteEndR ind end-pr;

23006  dcl-pr GetReqFiNum char(4);
23006    inString like(PrmHead);
23006  end-pr;

      //--------------------------------------------------------------
      // SQL options
      //--------------------------------------------------------------
       exec sql
         Set Option
           Commit    = *None,
           CloSqlCsr = *EndMod,
           DatFmt    = *ISO;


     C     *entry        plist
     C                   parm                    argv
      * Enable the clean up procedure.  When the program gets
      * cancelled procedure CleanUp will be called.
     C                   callb     'CEERTX'
     C                   parm                    pcleanup
     C                   parm                    *omit
     C                   parm                    *omit

      /free


         clear entry;
         entry    = %subst(argv:1);
       Exsr Initialization;
       hbstools_CommLog(660001:'[CHD1-01] Init done' +
         ' dtaqlib=' + w_dtaqlib);

         ChildSocketID = %dec(entry.ChildId:4:0);
       hbstools_CommLog(660001:'[CHD1-02] ChildSocketID=' +
         %char(ChildSocketID));

         // Receive the listen descriptor from the server
             Result = recvmsg(ChildSocketID:
                            %addr(msghdr):
                            flags);
       hbstools_CommLog(660001:'[CHD1-03] recvmsg result=' +
         %char(result) + ' sockaccept=' + %char(sockaccept));
        // format w_dtaqnm with pos 2 - 4 of job name
       bnkno = %subst(psjobnm:2:3);
       W_dtaqnm = 'HBS' + bnkno + 'RQ01';
              %subst(w_sendq:1:3) = 'HBS';
              %subst(w_sendq:4:6) = %editc(psjob#:'X');
              %subst(w_sendq:10:1) = 'Q';
           ChkDtaq2(w_sendq);

23003  W_dtaqctl = 'HBSCNTR' + bnkno ;
       hbstools_CommLog(660001:'[CHD1-04] Queues set' +
         ' dtaqnm=' + w_dtaqnm +
         ' dtaqctl=' + w_dtaqctl +
         ' sendq=' + w_sendq +
         ' lib=' + w_dtaqlib);

       DoW not *InLr;
       hbstools_CommLog(660001:'[CHD1-05] DoW top' +
         ' sockaccept=' + %char(sockaccept));

       // Accept a connection - moved to control program
         //  sockAccept  =  accept(sockListen:
         //                         %addr(sockaddrin):
         //                         LenSckAdIn);
         // ErrCheck(Sockaccept)  end program?
         // We don't currently use SSL
M02
M02      result = fcntl(sockaccept:
M02                  F_SETFL :
M02                  O_NONBLOCK);
M02      ErrCheck(result);


         // recieve data from accept socket and send confirmation till connection ends
         // go back to accept to get next connection request

                 //   rx = sleep(WaitTime);

                 If RecvDta() = *on;
                   Result = close(sockAccept);
                   Leave;
                 ENDIF;

         // check keyed dataq if any tasks for the worker
         CheckKeyQue(w_dtaqctl:w_dtaqlib:psjobnm);

         // check if instructions to end job and log
23003    if w_dta30  = 'ENDJOB';
23003           RcvStats = 'Receiver Job#: ' +   Psjobnm +
23003                %char(psjob#) + 'Normal End';
23003          hbstools_Commlog(660001:RcvStats);
23003         *inlr = *on;
23003    endif;

        ENDDO;

       // Worker Ending
       // write to recv that the recv job is ending

       WriteEndr();       //write to hbstrans/hbsreq
       Result = close(sockAccept);
21001  dltdtaq(w_sendq);
       EndTime = %timestamp();
       RcvStats = 'Receiver Job#: ' +
          %char(psjob#) + ' Start time: ' + %char(StartTime) +
         ' End time: ' + %char(EndTime) + ' Total Recv  ' +
         %char(%editc(TotRecv:'X')) +
          ' Total Send: ' + %char(%editc(TotSend:'X')) ;
       hbstools_Commlog(660001:RcvStats);
       result = close(ChildSocketID);
       *InLR = *on;
       Return;

       //--------------------------------------------------------\
       // Initialization Subroutine.                             |
       //--------------------------------------------------------/
       Begsr Initialization;

          StartTime = %timestamp();
          // read tables to determine what security to use
         Exec SQL
           Set Option
              commit = *none,
              CloSqlCsr = *endmod,
              Datfmt = *iso;

       // ChildSocketID = %int(%subst(argv: 7: 4));
       msg_accr = %addr(sockaccept);
       qdatainp = %addr(qdatain);
       msg_iov = %addr(iovec);
       msg_iovl = 1;

          w_timestmp = %timestamp();

M03    dsHBSSBSCTL = hbstools_GetDataArea('HBSSBSCTL':'*LIBL');
M03    w_dtaqlib = d_BankLib;

       Endsr;

      //---------------------------------------------------------
      // BldHeader - Build Header information for JSON Request
      //             from SQL table
      //---------------------------------------------------------
        dcl-proc BldHeader;
          dcl-pi *n varchar(2000);
            p_srvc char(40) value;
          END-PI;

          dcl-s RtnHdr varchar(2000);


         if h400ERR = *off and h500ERR = *off;
         RtnHdr = 'HTTP/1.1 200 OK' + CRLF +
                  'Server: Apache/2.2.14 (Win32) ' +  CRLF +
                 'User-Agent: http-api/1.38 ' + CRLF +
             'Content-Type: application/json; charset=utf-8 ' + CRLF +
             'Content-Length:';
          else;
         RtnHdr = 'HTTP/1.1 400 BAD REQUEST' + CRLF +
                  'Server: Apache/2.2.14 (Win32) ' +  CRLF +
                 'User-Agent: http-api/1.38 ' + CRLF +
             'Content-Type: application/json; charset=utf-8 ' + CRLF +
             'Content-Length:';
          endif;
          return RtnHdr;

        end-proc;
      //---------------------------------------------------------
      // CheckHeader- Find Content Length in Header for amount
      //              of data to receive in message
      //---------------------------------------------------------
        dcl-proc CheckHeader;
          dcl-pi *n int(10);
            i_buffer char(32768) const;
            w_starth int(10)  value;
          END-PI;

          // dcl-s w_buffer varchar(32000);
          dcl-s w_char char(1);
          dcl-s w_contlen char(5);
          dcl-s w_len int(10);
          dcl-s w_endh int(10);
          // dcl-s w_start int(10);
          dcl-s w_pos int(10);
          dcl-s w_indx1 int(10);
          dcl-s w_indx2 int(10);

          dcl-c ContLen const('Content-Length:');
          dcl-c numbers const('0123456789');
          dcl-c CR const(x'25');
          dcl-c Json const('{');
          dcl-c LF const(x'0d');
          // dcl-c MsgEnd const(x'0d25F00d25');
          if w_starth = 1;
             morereq = 1;
          endif;
          // GET SIZE OF REQUEST ALREADY RECIEVED WITH HEADER
          bufferlen = %len(%trim(I_BUFFER));
          w_buffer = i_buffer;

          // find content length on the next header in the recv buff
          W_START = 0;
          W_end = 0;
          W_endh = 0;
          w_start = %scan(ContLen:w_buffer:W_starth);

          // W_start will be the first position of content length in header
          iF W_START = 0;   // CONTENT LENGTH NOT FOUND IN REMAINDER OF H
            MOREREQ = 0;    // time to read more from recv buffer
            RETURN MOREREQ;
          ENDIF;

          // get content length from start to get start/end of request

          // find end of request

          if w_start > 0;
            w_start += 16;

             W_end  = %scan(MsgEnd:W_buffer:w_start);

            select;
            when %scan(CR:w_buffer:w_start) > 0;           //scan for end
              w_endh = %scan(CR:w_buffer:w_start);

            when %scan(LF:w_buffer:w_start) > 0;           //scan for end
              w_endh = %scan(LF:w_buffer:w_start);


            other;
            endsl;

          endif;

          w_pos = (w_endh - w_start);
          w_indx1 = 1;
          w_indx2 = 1;
          w_char = *blanks;

          For w_indx1 by 1 to w_pos;
            w_char = %subst(w_buffer:(w_start - 1) + w_indx1:1);


            if %scan(w_char:numbers) > 0;
              %subst(w_contlen:w_indx2:1) = w_char;
              w_indx2 += 1;
            endif;

            if w_indx2 > 5;
              leave;
           else;
             w_char = *blanks;
           endif;
          endfor;

          Monitor;
            if w_contlen = *blanks;        // no cL
              //
              //
            else;
              w_len = %int(%trim(w_contlen));
              Content_length = w_len;
            jsonstrt = %scan(Json:w_buffer:w_start);       //scan for start json

            if w_end = 0;
              if totlrcv <= (jsonstrt + Content_length) -1;
                 w_end = (jsonstrt + Content_length) -1;
              endif;
            endif;

            If JsonStrt = 0 and Content_length > 0;
          r_clob = *blanks;
          r_clob = '{"BaseRequest":null,"ResponseDetailCollection":[{' +
                    '"ResponseCode": 600009'   +
                    ',"ResponseMessage":"Received Header no JSON'  +
                    '"}],"Success":false}';


             H400Err = *on;
              senddtaerr();
              hbstools_CommLog(600009:'Header and no json' + rcvbuff );
              H400Err = *off;
              return 0;
            endif;
              return morereq;
            endif;

          on-error;
            return 0;
          endmon;

              return morereq;

        end-proc;
      //---------------------------------------------------------
      // ErrCheck - Check Error number
      //---------------------------------------------------------
        dcl-proc errcheck;
          dcl-pi *n int(10);
            result int(10);
          END-PI;

          if result < 0;
            perrno = $$errno;

            if errno <> 0;
              // errlog(errno);
            endif;

            return errno;
          endif;

          return 0;

         end-proc;

      //---------------------------------------------------------
      // ParseJSON - Parse JSON parameters
      //             Extracts ActivityId → w_guid
      //             Extracts ParentActivityId → w_pguid
      //---------------------------------------------------------
        dcl-proc ParseJSON;

           jsonerr = *off;

          // Get guid to write to recv file
          // check if docnode is null which is failure
          docnode = yajl_buf_load_tree(%addr(PrmJson:*data):
                                    %len(PrmJson):
                                    errmsg);
         IF docnode = *null;
          w_GUID  = *BLANKS;
           jsonerr = *on;
           hbstools_CommLog(660002:PrmJson);
           return;
         endif;


         IF errmsg  <> *blanks;
          w_GUID  = *BLANKS;
           jsonerr = *on;
           hbstools_CommLog(660002: 'DocNode Error' + errmsg);
          yajl_tree_free(docnode);
           return;
         Else ;
         // Get GUID (ActivityId) and ParentActivityId from JSON request
          ActvtyTrck = yajl_object_find(docnode:'ActivityTracking');
          node = yajl_object_find(ActvtyTrck:'ActivityId');
          w_GUID  = yajl_get_string(node);
          node = yajl_object_find(ActvtyTrck:'ParentActivityId');
          w_PGUID = yajl_get_string(node);
          if w_guid = *blanks ;
           jsonerr = *on;
           hbstools_CommLog(660002: 'Guid is blanks' );
          endif;
          yajl_tree_free(docnode);

          return;
         Endif;
        END-PROC;

      //---------------------------------------------------------
      // GetErr  - Retreive error codes descriptions
      //---------------------------------------------------------
        dcl-proc GetErr;
          dcl-pi *n char(200);
            err int(10) value;
          END-PI;

        dcl-s g_errmsg char(200);

         Exec SQL
           select lgdesc into :g_errmsg
             from hbslogdsc
             where lgid = :err;

         if g_errmsg = *blanks;
           g_errmsg = 'No matching error description';
         ENDIF;

         return g_errmsg;

        end-proc;

      //---------------------------------------------------------
      // ReadSQL - Retrieve response from HBRESP
      //           r_guid    = HSGUID  (= HTGUID = w_guid2)
      //           r_clob    = HSBODY  (JSON response payload)
      //---------------------------------------------------------
        dcl-proc ReadSQL;
          dcl-pi *n ind end-pi;

23005      reset ReadDta;
23005      r_clob_len = 0;

          Exec SQL
               Select HSGUID, HSBODY
               into :ReadDta
               from HBRESP
               where HSGUID = :w_guid;

          if sqlstate = '02000';
            return *off;
          ENDIF;

          if  CheckSQLstate(sqlstate) = 'C';
            MsgHdlr(MessageType : GetSQLCode(sqlcode): MessageFile ) ;
            return *off;
          endif ;

          return *on;

        end-proc;
      //---------------------------------------------------------
      // UpdtStat - Update send status in HBSTRANS
      //---------------------------------------------------------
        dcl-proc UpdtStat;
          dcl-pi *n;
            p_stat char(1) const;
          END-PI;

          dcl-s w_timestmp timestamp;
          dcl-s w_stat char(1);

          w_timestmp = %timestamp();
          w_stat = p_stat;

          Exec SQL
            update HBSTRANS set HTSNDSTS = :p_stat,
                               HTSNDTS  = :w_timestmp
              where HTGUID = :r_guid;

          return;

        end-proc;

      //---------------------------------------------------------
      // UpdtStatR - Update receive status in HBSTRANS
      //---------------------------------------------------------
        dcl-proc UpdtStatR;
          dcl-pi *n;
            p_stat char(1) const;
          END-PI;

          dcl-s w_timestmp timestamp;
          dcl-s w_stat char(1);

          w_timestmp = %timestamp();
          w_stat = p_stat;

          Exec SQL
            update HBSTRANS set HTRCVSTS = :p_stat,
                               HTRCVTS  = :w_timestmp
              where HTGUID = :w_guid2;

          return;

        end-proc;


      //---------------------------------------------------------
      // RecvDta - Recieve header then JSON request from bsl
      //           Write request to HBSTRANS/HBSREQ
      //           Send confirmation to BSL
      //           log errors
      //           Remain in this proc till SockAccept gets error
      //---------------------------------------------------------

        dcl-proc RecvDta;
          dcl-pi *n ind end-pi;



          RcvLen  = 0;
          totlrcv = 0;
          W_starth  = 1;
          etoasize =  0;
          iToGet = 32768;
          result = 0;
          result2 = 0;
          pbuffer = pbuffersav;
          clear     rcvbuff;


           ///  rx = sleep(WaitTime);          // for testing only

          dow *on;                       // loop exits only via Leave/Return

         CheckKeyQue(w_dtaqctl:w_dtaqlib:psjobnm);
23003    if w_dta30  = 'ENDJOB';
23003           RcvStats = 'Receiver Job#: ' +   Psjobnm +
23003                %char(psjob#) + 'Normal End';
23003          hbstools_Commlog(660001:RcvStats);
23003         Leave;
23003    endif;
                     // Iter here if content length found but not json do not reset below
            RcvStart = %timestamp();

              // We don't currently use SSL
              result = recv(sockaccept:pbuffer:iToGet:0);
              if result < 0;
                result2 = hbstools_ErrCnvrt(result);
              endif;


            select;

              when result < 0;
                if result2 = 3406;
                     If SendDta() = *off;
                       leave;        // socket error in send.. need to log
                     ENDIF;
M06               usleep(FiftyMilliseconds);
                  Iter;
                endif;
                // error in recv not 3406 or 0
                hbstools_CommLog(result2:'Error in Socket Recv');
                Return *ON;


              when result = 0;    // TCP graceful close — remote side closed connection
                // result=0 means the client sent a TCP FIN (EOF). On a non-blocking
                // socket this is the definitive signal that the connection is done.
                // Exit immediately — no retry is appropriate here.
                Return *On;

            ENDSL;

                //  Valid receive now process buffer



                totlrcv += result;         // total received
                etoasize = result;
                hbiconv(jha_ccsid_UTF_8:jha_ccsid_EBCDIC
                       :pbuffer:etoasize);  //convert rcvbuff from pbuffer to etoasize
                PBUFFER += result;


                  morereq  = CheckHeader(RcvBuff:w_starth);



               dow morereq > 0;    // get all requests from buffer
                  if w_end > 0 ;  //entire req parsed found end after starth
                     partialretry = 0;
                     WriteRecv();       //write to hbstrans/hbsreq
                     TotRecv += 1;      // total recieved
                     w_starth = jsonstrt + content_length + 1;  // starting point for next header
                     If SendDta() = *off;
                       leave;
                     ENDIF;
                   Else;   // partial request in buffer - w_end not found
                     // partialretry: counts recv attempts waiting for the rest of
                     // a message that arrived incomplete. After 5 attempts (~250ms),
                     // log and abandon the partial message.
                     partialretry += 1;
                     if partialretry < 6;
M06                    usleep(FiftyMilliseconds);
                       Iter; // go to recv x number of times
                     else;   // greater then 5 tries
                     morereq   = 0;
                     partialretry = 0;
                     hbstools_CommLog(600008:'Partial recv' + rcvbuff );
                             // log partial recieved in hbscomlog
                             // check if other requests on buffer to process
                     leave;
                     endif;
                  endif;

                   morereq  = CheckHeader(RcvBuff:w_starth);

               enddo;        // all requests and partial request parsed out of buffer


                     recvretry = 0;  // not used after result=0 fix; kept for safety
                     partialretry = 0;
                     w_starth = 1;       // new buffer recieved .. start at begin
                     ItoGet = 32768;    //Set Itoget back to 32768
                     totlrcv = 0;
                     w_end   = 0;
                     Morereq = 0;
                     etoasize =  0;
                     pbuffer = pbuffersav;        // clear buffer
                     clear     rcvbuff;

          ENDDO;        // continue to recieve as long as itoget > 0



          return *on;   //  error in recieve close sockaccept and end server worker

        end-proc;
      //---------------------------------------------------------
      // WriteRecv - After request buffer and all json request recieved
      //             Write transaction to HBSTRANS and request to HBSREQ
      //             w_guid2  = locally generated GUID (HTGUID key)
      //             w_guid   = JSON ActivityId  (HTRQAGUID)
      //             w_pguid  = JSON ParentActivityId (HTRQPGUID)
      //---------------------------------------------------------

        dcl-proc WriteRecv;
          dcl-pi *n ind end-pi;

23006       dcl-s ReqFiNum char(4);
23006       dcl-s Save_GUID like(w_GUID);
23006       dcl-s Save_JSON like(prmjson);

            h400err = *off;
            h500err = *off;

           PrmJson = %subst(rcvbuff:jsonstrt:content_length);
Kg03         PrmHead = %subst(rcvbuff:w_starth:jsonstrt - 1);


           PrmPtr = %addr(PrmJson);
           ParseJSON();

           w_timestmp = %timestamp();
           w_stat     = 'N';

23006      ReqFiNum = GetReqFiNum(PrmHead);
23006      if ReqFiNum <> *blanks and ReqFiNum <> d_FiNum;
23006        H400Err = *on;
23006        w_stat = 'E';
23006        Save_JSON = %trim(prmjson);
23006        prmjson = *blanks;
23006        prmjson = '{"BaseRequest":' +
23006          'null' +
23006        ',"ResponseDetailCollection":[{' +
23006               '"ResponseCode": 660003'   +
23006               ',"ResponseMessage":"FI Num ' + ReqFiNum + ' is invalid ' +
23006               'for ActivityID: ' + w_GUID +
23006               '"}],"Success":false}';
23006        r_clob = *blanks;
23006        r_clob = '{"BaseRequest":' +
23006          %trim(Save_JSON) +
23006        ',"ResponseDetailCollection":[{' +
23006               '"ResponseCode": 660003'   +
23006               ',"ResponseMessage":"FI Num ' + ReqFiNum + ' is invalid ' +
23006               'for ActivityID: ' + w_GUID +
23006               '"}],"Success":false}';
23006        Save_GUID = w_GUID;
23006        senddtaerr();
23006        w_GUID = Save_GUID;
23006        hbstools_CommLog(660003:
23006          'FI Num ' + ReqFiNum +
23006          ' is invalid for ActivityID: ' + w_GUID );
23006      endif;

           if jsonerr = *on;
              w_stat     = 'E';
              w_GUID =  hbstools_CrtGUID();
             H400Err = *on;
           Endif;

           // Generate local host GUID - this is the primary key in HBSTRANS
           exec sql VALUES QSYS2.GENERATE_UUID() INTO :w_GUID2;

           // Write master transaction record to HBSTRANS
           Exec SQL
             insert into HBSTRANS
              (HTGUID, HTRQPGUID, HTRQAGUID,
               HTTYPE, HTRCVSTS, HTSNDSTS, HTREQHDR)
             values
              (:w_guid2, :w_pguid, :w_guid,
               'IN', :w_stat, 'N', :prmhead);

           if sqlstate <> '00000';
             hbstools_CommLog(660005:
               'HBSTRANS insert failed SQLSTATE=' + sqlstate + 
                ' GUID=' + w_guid2);
             return *off;
           endif;

           // Write request body to HBSREQ
           Exec SQL
             insert into HBSREQ
              (HRGUID, HRBODY)
               values (:w_guid2, :prmjson);

           if sqlstate <> '00000';
             hbstools_CommLog(660005:
               'HBSREQ insert failed SQLSTATE=' + sqlstate + 
                ' GUID=' + w_guid2);
             return *off;
           endif;

           UpdtStatR('Y');

          // Write to receive dataq for handler - use w_guid2 (local GUID) as queue entry
              %subst(w_qdata:1:36) = w_guid2;
              %subst(w_qdata:37:3) = 'HBS';
              %subst(w_qdata:40:6) = %editc(psjob#:'X');
              %subst(w_qdata:46:1) = 'Q';
              ChkDtaq(w_dtaqnm);
              recvstart = 'Socket Receive Start' +  %Char(rcvstart);
              hbstools_CrtLog(w_GUID2
                             :'GUIDLOG':''
                             :'540000':%char(recvstart)
                             :Procname:psjobnm
                             :%char(psjob#):'Y');

              //   HBSTOOLS_RECVLOG(w_guid:w_guid2);
              hbstools_CrtLog(W_GUID2
                             :'GUIDLOG':''
                             :'540000':''
                             :Procname:psjobnm
                             :%char(psjob#):'Y');

              IF H400ERR = *OFF;
                SndDtaq(w_dtaqnm:w_dtaqlib:W_qlen:
                    w_qdata);
                ENDIF;



          return *off;

        end-proc;
      //---------------------------------------------------------
      // ChkDtaq - check if dataq exists
      //---------------------------------------------------------
        dcl-proc ChkDtaq;
          dcl-pi *n ind;
            p_Dtaq char(10);
          END-PI;

          dcl-s w_cmd char(256);
          dcl-s w_cmdln packed(15:5);

          w_cmd = 'CHKOBJ OBJ(*LIBL/' +
                  %trim(p_Dtaq) + ') OBJTYPE(*DTAQ)';
          w_cmdln = %len(%trim(w_cmd));

          If system(w_cmd) <> 0;

            w_cmd = *blanks;

M03         w_cmd = 'CRTDTAQ DTAQ(' + %trim(w_DtaqLib) + '/' + %trim(p_dtaq) +
                    ') MAXLEN(46) TEXT(''HBS Send Job Data Queue for ' +
                    %trim(psjobnm) + ''') AUT(*ALL)';

            w_cmdln = %len(%trim(w_cmd));

            if system(w_cmd) <> 0;
              return *on;
            ENDIF;

          endif;

          return *off;

        END-PROC;
      //---------------------------------------------------------
      // ChkDtaq2 - check if dataq exists (send queue)
      //---------------------------------------------------------
        dcl-proc ChkDtaq2;
          dcl-pi *n ind;
            p_Dtaq char(10);
          END-PI;

          dcl-s w_cmd char(256);
          dcl-s w_cmdln packed(15:5);

          w_cmd = 'CHKOBJ OBJ(*LIBL/' +
                  %trim(p_Dtaq) + ') OBJTYPE(*DTAQ)';
          w_cmdln = %len(%trim(w_cmd));

          If system(w_cmd) <> 0;

            w_cmd = *blanks;


M03         w_cmd = 'CRTDTAQ DTAQ(' + %trim(w_DtaqLib) + '/' + %trim(p_dtaq) +
                    ') MAXLEN(46) TEXT(''HBS Send Job Data Queue for ' +
                    %trim(psjobnm) + ''') AUT(*ALL)';

            w_cmdln = %len(%trim(w_cmd));

            if system(w_cmd) <> 0;
              return *on;
            ENDIF;

          endif;

          return *off;

        END-PROC;

      //---------------------------------------------------------
      // SendDta - Send JSON to client
      //           Reads response from HBRESP via ReadSQL
      //---------------------------------------------------------
        dcl-proc SendDta;
          dcl-pi *n ind end-pi;

23005   //   dcl-s SndBuff varchar(32000);
23005      dcl-s SndBuff varchar(2000000);

          SndBuff = *blanks;
23sas     BigBuffero = *blanks;
          BigBuffer = *blanks;
          w_guid    = *blanks;

         //IF H400err or h500err send back correct error header
         //turn off h500err and h400err

           if h400err or h500err;
             senddtaerr();
              h400err = *off;
               h500err = *off;
             return *off;
             endif;

          //ELSE - CHECK DATAQ FOR A RESPONSE
         //CHECK SEND DATA Q TO SEE IF ANYTHING READY TO SEND
              %subst(w_sendq:1:3) = 'HBS';
              %subst(w_sendq:4:6) = %editc(psjob#:'X');
              %subst(w_sendq:10:1) = 'Q';
           ChkDtaq2(w_sendq);
           RcvDtaq(w_sendq:w_DTAQlib: w_qlen2: w_guid: 0);
           If w_guid  <> *blanks;

          If ReadSQL() = *on;
             // check r_clog if it is an end request
             IF  %subst(R_CLOB:1:10) = 'END WORKER';
                 return *off;
             ENDIF;
             // check r_clog if it is an end request
23005   //      SndBuff = %trimr(r_clob) + CRLF + CRLF;
23005         SndBuff = %trimr(r_clob_data) + CRLF + CRLF;
             Bigbuffer = BldHeader('TextMessaging') +
                            %trim(%char(%editc(%len(SndBuff):'Z'))) +
                            CRLF + CRLF + %trim(SndBuff);

23sas        Bigbuffero = Bigbuffer;

23sas        bufferlen = %len(%trim(bigbuffero));

             BUFFSENT = 0;
             totr = 0;
             retry = 0;
             dou totr   = bufferlen;
              // We don't currently use SSL
              result = send(sockaccept:%addr(bigbuffero:*data):bufferlen:0);

               totr += result;
               if result < 0;
                 result2 = hbstools_ErrCnvrt(result);
                 hbstools_Commlog(result2:'Error in Socket send ' +
                                 %trim(w_guid));
                 result = close(sockaccept);
                 return *off;
                 leave;
               ENDIF;
               retry +=1;
               if retry > 50;
                 leave;
               ENDIF;

         // recieve completed
          if  totr   = bufferlen;
             // HBSTOOLS_sendlog(w_guid);
             hbstools_CrtLog(W_GUID
                            :'GUIDLOG':''
                            :'540001':''
                            :Procname:psjobnm
                            :%char(psjob#):'Y');
             UpdtStat('Y');
             TotSend += 1;
          endif;

          ENDDO;

          ENDIF;
          ENDIF;


          return *on;

        end-proc;

      //---------------------------------------------------------
      // SendDtaErr - Send error header to client
      //---------------------------------------------------------
        dcl-proc SendDtaErr;
          dcl-pi *n ind end-pi;

          dcl-s SndBuff varchar(32000);

          BigBuffer = *blanks;
          w_guid    = *blanks;

          SndBuff = %trimr(r_clob) + CRLF + CRLF;
          Bigbuffer = BldHeader('TextMessaging') +
                            %trim(%char(%editc(%len(SndBuff):'Z'))) +
                            CRLF + CRLF + %trim(SndBuff) ;


          hbiconv(jha_ccsid_EBCDIC:jha_ccsid_UTF_8
                                  :%Addr(bigbuffer:*Data)
                                  :%Len(bigbuffer));

          bufferlen = %len(%trim(bigbuffer));

          totr = 0;
          retry = 0;
          dou totr   = bufferlen;
              // We don't currently use SSL
              result = send(sockaccept:%addr(bigbuffer:*data):bufferlen:0);

            totr += result;
            if result < 0;
              result = close(sockaccept);
              SndBuff = *blanks;
               return *off;
              leave;
            ENDIF;
            retry +=1;
            if retry > 50;
              leave;
            ENDIF;


          ENDDO;

          SndBuff = *blanks;

          return *on;

        end-proc;

      //----------------------------------------------------------------------
23006 // Get the Request FI Number from the Header string
      //----------------------------------------------------------------------
23006  dcl-proc GetReqFiNum;
         dcl-pi *n char(4);
           inString like(PrmHead);
         end-pi;

         dcl-s idx1 int(10);
         dcl-s idx2 int(10);
         dcl-s idx3 int(10);
         dcl-s myFiNum char(4) inz(*blanks);
         dcl-s myError ind inz(*off);

         reset myFiNum;
         reset myError;

         idx1 = 0;
         for idx2 = 1 to 3;
           idx1 = %scan('/' : inString: idx1+1);
         endfor;
         if idx1 = 0;
           myError = *on;
         endif;

         if not myError;
           idx3 = %scan('/' : inString: idx1+1);
           if idx3 = 0;
             myError = *on;
           else;
             myFiNum = %subst(inString:idx1+1: idx3-idx1-1);
           endif;
         endif;

         if myFiNum = *blanks;
           myError = *on;
         endif;

         if myError = *on;
           return *blanks;
         else;
           return myFiNum;
         endif;

23006   end-proc;
      /end-free

      *--------------------------------------------------------\
      *  Clean up procedure.                                   |
      *--------------------------------------------------------/
     P cleanup         b
     D cleanup         pi
     D   info                          *

23003           Rcvstats = *blanks;
23003           RcvStats = 'Receiver Worker Job#: ' +   Psjobnm +
23003                %char(psjob#) + 'Abnormal End';
23003          hbstools_Commlog(660001:RcvStats);
23003           Rcvstats = *blanks;

     C                   if        sockaccept >= 0
     C                   eval      result = close(sockaccept)
     C                   callp     errcheck(result)
     C                   endif
     C                   eval      *inlr = *on
     C                   return

     P cleanup         e

      *--------------------------------------------------------\
      *  Delete data queue for worker job activity             |
      *--------------------------------------------------------/
     P Dltdtaq         b
     D Dltdtaq         pi
     D   p_dtaqnm                    10a   const

      /free

        qcmd = *blanks;
        qcmdln = 512;

21001   qcmd = 'DLTDTAQ DTAQ(' + %trim(w_dtaqlib) + '/' +
                        %trim(p_dtaqnm) + ')';
        callp(e) cmdexc(qcmd:qcmdln);

     P Dltdtaq         e

      //---------------------------------------------------------
      // WriteEndr - Write end-of-receiver record to HBSTRANS/HBSREQ
      //---------------------------------------------------------

        dcl-proc WriteEndr;
          dcl-pi *n ind end-pi;

       // write to hbstrans/hbsreq that the recv job is ending
           Rcvbuff = 'POST /SubsystemControl HTTP/1.1 '  +
                   cendR + CRLF ;
           jsonstrt = 32;
           content_length = 26;

           PrmJson = %subst(rcvbuff:jsonstrt:content_length);
           PrmHead = %subst(rcvbuff:1:jsonstrt - 1);

           PrmPtr = %addr(PrmJson);

           w_timestmp = %timestamp();
           w_stat     = 'N';

           // Generate local host GUIDs for the end record
              w_GUID2 = hbstools_CrtGUID();
              w_GUID  = hbstools_CrtGUID();

           Exec SQL
             insert into HBSTRANS
              (HTGUID, HTRQPGUID, HTRQAGUID,
               HTTYPE, HTRCVSTS, HTSNDSTS, HTREQHDR)
             values
              (:w_guid2, :w_guid, :w_guid,
               'IN', :w_stat, 'N', :prmhead);

           Exec SQL
             insert into HBSREQ
              (HRGUID, HRBODY)
               values (:w_guid2, :prmjson);


          return *off;

        end-proc;
23003
      //---------------------------------------------------------
      // CheckKeyQue - Check Controller queue and react to requests
      //               Receives only entries matching this job (psjobnm key).
      //               Replaces QRCVDTAQ API with SQL equivalent
      //               (aligned with HBSHANDLR.CheckKeyQue pattern).
      //---------------------------------------------------------
        dcl-proc CheckKeyQue;
          dcl-pi *n int(10);
            p_dtaqnm char(10) const;
            p_dtaqlib char(10) const;
            p_keydata char(10) const;
          end-pi;

          // Receive only entries matching this job's key from the controller queue.
          // Matched entry is removed. Result is placed in global w_dta30.
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
