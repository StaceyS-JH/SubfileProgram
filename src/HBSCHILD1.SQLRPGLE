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

         // execute iSeries system command
         //include qcpysrc,systemcpy


      *****************************************************************
      * Constants
      *****************************************************************

M06  D FiftyMilliseconds...
M06  D                 s             10i 0 inz(0050000)
     D AF_INET         c                   const(2)
     D AF_UNIX         c                   const(1)
     D INADD_NONE      c                   const(-1)
     D INADDR_ANY      c                   const(0)
     D REUSEADDR       c                   const(55)
     D SCK_STREAM      c                   const(1)
     D SOCK_DGRAM      c                   const(2)
     D SOL_socket      c                   const(-1)
23001D TCP_NODELAY     C                   10
23001D IPPROTO_IP      C                   CONST(0)



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
     d entry           ds                  qualified
     d  ChildId                      10a
23001d  Gsecurity                     1a
23001d  Appid                        50a
     D sockaddrin      ds
     D   familyin                     5i 0
     D   portin                       5u 0
     D   addressin                   10u 0
     D   zeroin                       8

     D msghdr          ds
     D   msg_name                      *   inz(*null)
     D   msg_namel                   10i 0 inz(0)
     D   msg_iov                       *   inz(%addr(iovec))
     D   msg_iovl                    10i 0 inz(1)
     D   msg_accr                      *   inz(*null)
     D   msg_accrl                   10i 0 inz(%size(sockaccept))

     D iovec           ds
     D   qdatainp                      *
     D   qdatalen                    10i 0 inz(257)

     D inherit         ds
     D   in_flags                    10u 0 inz(0)
     D   in_pgroup                   10i 0 inz(0)
     D   in_sigmask1                 10u 0 inz(0)
     D   in_sigmask2                 10u 0 inz(0)
     D   in_sigdef1                  10u 0 inz(0)
     D   in_sigdef2                  10u 0 inz(0)

23003D RcvDtaqKey      pr                  extpgm('QRCVDTAQ')
23003D                               10a   const
23003D                               10a   const
23003D                                5  0
23003D                               10a
23003D                                5  0 const
23003D                                2a   const
23003D                                3  0 const
23003D                               10a   const
23003D                                3  0 const
23003D                               10a   const
23003D                               10a   Const
23003D                                5  0 Const
23003D                               10a   Const


      // Carriage Return Line Feed - Hex value of these two characters
       dcl-c CRLF const(x'0d25');
       dcl-c cEndr const('"HBServiceType":"ENDRECV"');


       // ReadDta: r_guid=HSGUID (= HTGUID = w_guid2), r_clob=HSBODY
       dcl-ds ReadDta;
         r_guid   char(36);
23005     r_clob sqltype(clob:2000000) inz('');
       END-DS;

M03    dcl-ds HBSSBSCTL dtaara(*usrctl);
M03      d_SBSName char(10);
M03      d_SBSLib char(10);
M03      d_BankLib char(10);
M03      d_FINum char(4);
M03      d_LocalIP char(16);
M03    end-ds;

     D*---------------------------------------------------------------------
     D* Stand Alone Fields - TOP
     D*---------------------------------------------------------------------
23003D w_dta30         s             10a
     D qcmd            s            512
     D qcmdln          s             15  5
     D qdatain         s           5000
     D qdata           s           5000
     D sockaccept      s             10i 0 inz(-1)
     D socklisten      s             10i 0 inz(-1)
     D ChildSocket10   s             10a
     D ChildSocket4    s              4a
     D ChildSocketID   s             10i 0
     D HowManyMore     s              5i 0
     D Index           s              5i 0
     D HBSBuffer       s            256a   based(BufferPtr)
     D argv            s           1024a
     D Data            s           1024a
     D pbuffer         s               *
     D pbuffersav      s               *   inz(%addr(rcvbuff))
     D buffer          s          32000
     D etoasize        s             10  0
M02  D @SecondaryFailed...
M02  D                 c                   const('Secondary Receive Failed.')
M02  D F_SETFL         s             10I 0 Inz(7)
M02  D errWouldBlock   s             10i 0 inz(3406)
M02  D ErrorCode       s             10i 0
M02  D RetryCounter    s              5i 0
M02  D RecvRetry       s              5i 0
M02  D t_timestamp     s               z
     D flags           s             10i 0 inz(0)
     D lensckadin      s             10i 0 inz(%size(sockaddrin))
     D ReceiveError    s               n   inz(*off)
     d WaitTime        s              5  0 inz(060)                             Seconds
     D null            s              1    inz(x'00')
     D w_dtaqnm        s             10a   inz('HBS000RQ01')
kkg  D w_dtaqctl       s             10a   inz('HBSCNTR')
M03  D w_dtaqlib       s             10a
     D w_dta           s             10a
23003D w_dtactl        s             10a
     D w_len           s              5  0 inz(10)
     D w_wait          s              5  0 inz(0)
     D w_keyord        s              2a   inz('EQ')
     D w_keylen        s              3  0 inz(0)
     D w_keydata       s             10a   inz(*blanks)
     D w_sendlen       s              3  0 inz(8)
     D w_sendinf       s              8a   inz(*blanks)
     D totr            s             10I 0 inz(0)
     D retry           s              3  0 inz(0)
23001d rx              s             10i 0 inz(0)
23001D gSecurity       S               n
23001D wwOpt           s             10i 0
          dcl-s rcvbuffl   int(10);
          dcl-s w_content# int(10);
          dcl-s w_reqparsed int(10);
          dcl-s w_end int(10);
          dcl-s w_starth int(10);
23003     dcl-s rc int(10);

     D totrecv         s              9  0 inz(0)
     D totsend         s              9  0 inz(0)
       dcl-s rcvLen int(10);
       dcl-s buffsent int(10);
23002  //dcl-s bigbuffer varchar(32767);
23sas  dcl-s bigbuffer varchar(2000000);
23sas  dcl-s bigbuffero varchar(2000000) ccsid(*utf8);
       dcl-s errmsg varchar(500);
       dcl-s errcee char(1);
       dcl-s bnkno  char(3);
       dcl-s end ind;
       dcl-s jsonerr ind;
       dcl-s h400err ind;
       dcl-s h500err ind;
       dcl-s MsgSize int(10:0);
       dcl-s pIgnoreMsg pointer(*proc) inz(%paddr('JHIGNM'));
sas    //dcl-s PrmJson varchar(2000);
sas    dcl-s PrmJson varchar(4000);
       dcl-s PrmHead varchar(2000);
       dcl-s PrmPtr pointer;
       dcl-s r_attmpt packed(3);
       dcl-s rcvbuffer char(1000);
       dcl-s cnvrtrcv varchar(1000);
       dcl-s rcvrslt varchar(32767);
       dcl-s w_qlen packed(5) inz(46);
       dcl-s w_qdata char(46);
       dcl-s w_qlen2 packed(5) inz(36);
       dcl-s w_qdata2 char(36);
       dcl-s w_pqlen packed(5) inz(10);
       dcl-s w_pqkeylen packed(3) inz(10);
       dcl-s w_pqkeydta char(10);
       dcl-s w_pqdata char(10);
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
       dcl-s iPos int(10) inz(1);
       dcl-s iToGet int(10);
       dcl-s o_nonblock int(10) inz(128);
       dcl-s result int(10);
       dcl-s result2 int(10);
       dcl-s RCVBuff char(4096);
       dcl-s RcvStart   timestamp;
       dcl-s StartTime  timestamp;
       dcl-s EndTime  timestamp;
       dcl-s RCVStats char(200);
       dcl-s RCVErr   char(200);
       dcl-s Recvstart char(50);

       dcl-s gAppID char(100);
       dcl-s gEnvHndle pointer;
       dcl-s gIndx int(10);
       dcl-s gSrvrNam char(20) dim(10);
       dcl-s gSsnHndle pointer;
       dcl-s gSsnType char(4);
23001  dcl-c MsgEnd const(x'0d25F00d25');
23001     dcl-s w_start int(10);
23001     dcl-s w_buffer varchar(32000);

      * ----- Unsure of lines above ----
     D pcleanup        s               *   procptr    inz(%paddr('CLEANUP'))



23001  /define HBSGSK_Proto
23001  /include qcpysrc,HBSGSKM
23001  /undefine HBSGSK_Proto

23003 * Check Controler queue
23003D CheckQue        pr            10i 0 opdesc
23003D   p_dtaqnm                    10a   const

      * Delete data queue for Worker Jobs.
     D Dltdtaq         pr
     D   p_dtaqnm                    10a   const


      * QCMDEXC to run commands.
     D cmdexc          pr                  extpgm('QCMDEXC')
     D   cmdtxt                            like(qcmd)
     D   cmdlngth                          like(qcmdln)

      * Prototype cleanup procedure.
     D cleanup         pr
     D   Info                          *
      * The Accept a connection.  Returns CONNECTION's socket descriptor.
     D accept          pr            10i 0 extproc('accept')
     D   socketdesc                  10i 0 value
     D   sockaddrss                    *   value
     D   addresslen                  10i 0
      * Receive data on socket.  Returns -1 if error, else # of bytes rec'vd
     D recv            pr            10i 0 extproc('recv')
     D   socketdesc                  10i 0 value
     D   buffer                        *   value
     D   bufferlen                   10i 0 value
     D   flags                       10i 0 value
      * Close socket.
     D close           pr            10i 0 extproc('close')
     D   socketdesc                  10i 0 value
      * The recvmsg function returns a -1 if unsuccessful.
     D recvmsg         pr            10i 0 extproc('recvmsg')
     D   socketdesc                  10i 0 value
     D   msghdr                        *   value
     D   flags                       10i 0 value
      * The Send function returns a -1 if unsuccessful. If
      * successful, it returns the number of bytes sent.
     D send            pr            10i 0 extproc('send')
     D   socketdesc                  10i 0 value
     D   buffer                        *   value
     D   bufferlen                   10i 0 value
     D   flags                       10i 0 value
      // The SetSockOpt function returns a -1 if unsuccessful.
23001D setsockopt      pr            10i 0 extproc('setsockopt')
23001D   socketdesc                  10i 0 value
23001D   level                       10i 0 value
23001D   optionname                  10i 0 value
23001D   optionvalu                    *   value
23001D   optionlen                   10i 0 value



       dcl-pr ChkDtaq ind;
         p_Dtaq char(10);
       end-pr;


       dcl-pr ChkDtaq2 ind;
         p_Dtaq char(10);
       end-pr;



      * The FCntl function returns a -1 if unsuccessful.

     D fcntl           pr            10i 0 extproc('fcntl')
     D                               10i 0 value
     D   F_SETFL                     10i 0 value
     D   O_NONBLOCK                  10i 0 value options(*nopass)

      * Create Data queue for Recieve.
     D crtdtaq         pr
     D   p_dtaqnm                    10a   const
     D               euds                  extname(jhapar)



       dcl-pr ReadSQL ind end-pr;

       dcl-pr UpdtStat;
         stat char(1) const;
       END-PR;


       dcl-pr UpdtStatR;
         stat char(1) const;
       END-PR;


       dcl-pr CheckHeader int(10);
         i_buffer char(32000) value;
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

         ChildSocketID = %dec(entry.ChildId:4:0);

         // Receive the listen descriptor from the server
             Result = recvmsg(ChildSocketID:
                            %addr(msghdr):
                            flags);
        // format w_dtaqnm with pos 2 - 4 of job name
       bnkno = %subst(psjobnm:2:3);
       W_dtaqnm = 'HBS' + bnkno + 'RQ01';
              %subst(w_sendq:1:3) = 'HBS';
              %subst(w_sendq:4:6) = %editc(psjob#:'X');
              %subst(w_sendq:10:1) = 'Q';
           ChkDtaq2(w_sendq);

23003  W_dtaqctl = 'HBSCNTR' + bnkno ;

       DoW not *InLr;

       // Accept a connection - moved to control program
         //  sockAccept  =  accept(sockListen:
         //                         %addr(sockaddrin):
         //                         LenSckAdIn);
         // ErrCheck(Sockaccept)  end program?
23001       If gSecurity = *on;
23001              gAppID = entry.appid;
23001           gSSnType = 'RECV';

             //  this line is for debug purposes only

                  //  rx = sleep(WaitTime);
23001         MONITOR;
23001         If hbssock_CreateHandle(gEnvHndle:gAppID:gSSnType:gSecurity) <> 0;
23001           hbstools_Commlog(560010);
23001           *inlr = *on;
23001           Iter;
23001         ENDIF;
23001 * Disable Nagle's Algorithm
23001c                   eval      wwOpt = 1
23001c                   eval      result = setsockopt( SockAccept
23001c                                            : IPPROTO_IP
23001c                                            : TCP_NODELAY
23001c                                            : %addr(wwOpt)
23001C                                            : %size(wwOpt) )
23001         If hbssock_CreateSession(sockAccept:gEnvHndle:gSsnHndle) <> 0;
23001                 hbstools_Commlog(560020);
23001           *inlr = *on;
23001           Iter;
23001         ENDIF;
23001         ON-ERROR;
23001            hbstools_CommLog(699999:'ERROR CALLING HBSGSKM');
23001         ENDMON;

            ENDIF;
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

kkg      // check keyed dataq if any tasks for the worker
kkg      CheckQue(w_dtaqctl);

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
          hbssock_CloseSession(gSsnHndle);
          hbssock_CloseHandle(gEnvHndle);

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
23001     if entry.gsecurity = 'Y';
23001       gSecurity = *on;
23001     else;
23001       gSecurity = *off;
23001     endif;

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

M03    in HBSSBSCTL;
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
            i_buffer char(32000) value;
            w_starth int(10)  value;
          END-PI;

          // dcl-s w_buffer varchar(32000);
          dcl-s w_char char(1);
          dcl-s w_contlen char(4);
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

            if w_indx2 > 4;
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
            update HBSTRANS set HTSNDSTS = :p_stat
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
            update HBSTRANS set HTRCVSTS = :p_stat
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
          iToGet = 10000;
          result = 0;
          result2 = 0;
          pbuffer = pbuffersav;
          clear     rcvbuff;


           ///  rx = sleep(WaitTime);          // for testing only

          dow itoget > 0;                // stay in loop until end of connection

kkg      CheckQue(w_dtaqctl);
23003    if w_dta30  = 'ENDJOB';
23003           RcvStats = 'Receiver Job#: ' +   Psjobnm +
23003                %char(psjob#) + 'Normal End';
23003          hbstools_Commlog(660001:RcvStats);
23003         Leave;
23003    endif;
                     // Iter here if content length found but not json do not reset below
            RcvStart = %timestamp();

23001       If gSecurity = *on;
23001          result = 0;
23001          result2 = 0;
23001         result = hbssock_Read(gSsnHndle:pbuffer:iToGet:rcvLen);

23001         If result = 0;
23001            If rcvLen = 0;
23001                hbstools_CommLog(result:'Zero recieved zero result');
23001                result  =  -1;
23001            else;
23001
23001            If rcvlen > 0;
23001              result = rcvLen;
23001                hbstools_CommLog(result:'Result 0 and rcvlen');
23001              result2 = 0;
23001            endif;
23001            endif;

23001         else;                    // result not 0
23001           if result = 502;
23001              result2 = 3406;
23001             result  =  -1;
23001           else;
23001
23001           if result  <> 0 and result <> 502;
23001                hbstools_CommLog(result:'After read  not 502');
23001             result2 =  result;
23001             result  =  -1;
23001            endif;
23001         ENDIF;    // result not zero
23001         ENDIF;    // READ FOR SSL SECURITY

23001       else;
              result = recv(sockaccept:pbuffer:iToGet:0);
              if result < 0;
                result2 = hbstools_ErrCnvrt(result);
              endif;
            ENDIF;


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


              when result = 0;    //  nothing to recieve iter
                usleep(FiftyMilliseconds);
                recvretry += 1;
                if recvretry > 60;
                   recvretry = 0;
                   hbstools_CommLog(600010:'Max return 0');
                   Return *On;
                Endif;
                iter;            // usleep and iter X number of times

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
                     recvretry = 0;
                     WriteRecv();       //write to hbstrans/hbsreq
                     TotRecv += 1;      // total recieved
                     w_starth = jsonstrt + content_length + 1;  // starting point for next header
                     If SendDta() = *off;
                       leave;
                     ENDIF;
                   Else;   // partial request in buffer - w_end not found
                     recvretry += 1;
                     if recvretry < 6;
M06                    usleep(FiftyMilliseconds);
                       Iter; // go to recv x number of times
                     else;   // greater then 5 tries
                     morereq   = 0;
                     recvretry = 0;
                     hbstools_CommLog(600008:'Partial recv' + rcvbuff );
                             // log partial recieved in hbscomlog
                             // check if other requests on buffer to process
                     leave;
                     endif;
                  endif;

                   morereq  = CheckHeader(RcvBuff:w_starth);

               enddo;        // all requests and partial request parsed out of buffer


                     recvretry = 0;
                     w_starth = 1;       // new buffer recieved .. start at begin
                     ItoGet = 10000;    //Set Itoget back to 10000
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
           w_GUID2 = hbstools_CrtGUID();

           // Write master transaction record to HBSTRANS
           Exec SQL
             insert into HBSTRANS
              (HTGUID, HTRQPGUID, HTRQAGUID, HTTYPE, HTRCVSTS, HTSNDSTS)
               values (:w_guid2, :w_pguid, :w_guid, 'RQ', :w_stat, 'N');

           // Write request header and body to HBSREQ
           Exec SQL
             insert into HBSREQ
              (HRGUID, HRHEADER, HRBODY)
               values (:w_guid2, :prmhead, :prmjson);

          // Write to receive dataq for handler - use w_guid2 (local GUID) as queue entry
              %subst(w_qdata:1:36) = w_guid2;
              %subst(w_qdata:37:3) = 'HBS';
              %subst(w_qdata:40:6) = %editc(psjob#:'X');
              %subst(w_qdata:46:1) = 'Q';
              ChkDtaq(w_dtaqnm);
              recvstart = 'Socket Receive Start' +  %Char(rcvstart);
              hbstools_Actvty(w_GUID:W_GUID2:540000:recvstart);

              //   HBSTOOLS_RECVLOG(w_guid:w_guid2);
                hbstools_Actvty(w_GUID:W_GUID2:540000);

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
23001             If gSecurity = *on;
23001               buffsent = 0;
23001
23001               result = hbssock_write(gSsnHndle:%addr(bigbuffer:*data)
23001                                      :bufferlen:buffsent);
23001
23001               If buffsent = 0;
23001                 RESULT = -1;
23001                 hbstools_Commlog(45003:'SSL write fail for:'  +
23001                                    %trim(w_guid));
23001               eLSE;
23001                 result = buffsent;
23001               endif;
23001
23001             else;
23sas             result = send(sockaccept:%addr(bigbuffero:*data):bufferlen:0);
23001          Endif;

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
                hbstools_Actvty(w_GUID:W_GUID:540001);
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
23001       If gSecurity = *on;
23001               buffsent = 0;

23001               result = hbssock_write(gSsnHndle:%addr(bigbuffer:*data)
23001                                      :bufferlen:buffsent);

23001               If buffsent < bufferlen;
23001                 hbstools_Commlog(45003:'SSL write fail for:'  +
23001                                    %trim(w_guid));
23001               endif;
23001       else;
              result = send(sockaccept:%addr(bigbuffer:*data):bufferlen:0);
23001       Endif;

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
              (HTGUID, HTRQPGUID, HTRQAGUID, HTTYPE, HTRCVSTS, HTSNDSTS)
               values (:w_guid2, :w_guid, :w_guid, 'RQ', :w_stat, 'N');

           Exec SQL
             insert into HBSREQ
              (HRGUID, HRHEADER, HRBODY)
               values (:w_guid2, :prmhead, :prmjson);


          return *off;

        end-proc;
23003
23003 *--------------------------------------------------------\
      *  Check Controller queu and react to requests           |
      *--------------------------------------------------------/
     P CheckQue        b
     D CheckQue        pi            10i 0 opdesc
     D   p_dtaqnm                    10a   const

     D ck_datqnm       s             10a   inz(*blanks)
     D ck_datlib       s             10a   inz(*blanks)
     D w_len           s              5  0 inz(10)
     D w_wait          s              5  0 inz(0)
     D w_keyord        s              2a   inz('NE')
     D w_keylen        s              3  0 inz(10)
     D w_keydata       s             10a   inz(*blanks)
     D w_sendlen       s              3  0 inz(8)
     D w_sendinf       s              8a   inz(*blanks)
     D DataQLen        s              5  0 Inz(40)
     D Qdlen           s              5  0

21001D w_ErrDS         ds
21001D   w_prvbyte             1      4i 0
21001D   w_aftbyte             5      8i 0
21001D   w_excpID              9     15
21001D   w_reserv             16     16


      /free
          // change to recieve only entries for B###C job matching the controljob
          // dataq entry should be deleted when received
23003     w_dta30  = *blanks;
23003     ck_datqnm = p_dtaqnm;
23003     ck_datlib = W_dtaqlib;
23003
23003     qdlen = %len(W_dta30);
23003     RcvDtaqKey(ck_datqnm:ck_datlib:qdlen:w_dta30: 0
23003                    : 'EQ' : 10 : psjobnm : 0 :*Blanks
                    : '*NO' : DataqLen : w_ErrDS) ;

        return rc;
      /end-free
23003P CheckQue        e
23001
