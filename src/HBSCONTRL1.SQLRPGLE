M03    ctl-opt option(*srcstmt : *nodebugio);
M03    ctl-opt bnddir('HBSBIND':'JHIGNM':'JHBIND':'QC2LE') DECEDIT('0.');
M03    ctl-opt dftactgrp(*NO);
M03    ctl-opt actgrp('BSL');
sasn   ctl-opt bnddir('NOXDB');


vev01 // 12/12/25 V Everett #1179375 Modify check of JHEOD by core

24001 // 04/23/23 V Everett #1179375 Core agnostic changes
23004 // 09/05/23 S Smith #1177516 - psds changes
23003 // 05/22/23 Greene   #1176052 - Start/End FI and keyed control q
23002 // 04/11/23 Greene   #xxxxxxx - Option to upgrade connection to SSL/TLS
23001 // 23001 - Add Scheduler Logic
m03   // 09/02/22 - VEverett - add create receive data queue

      // Create command
      *> CRTSQLRPGI OBJ(&O/&ON) SRCFILE(&L/QRPGLESRC) -
      *> OBJTYPE(*PGM) OUTPUT(*NONE) RPGPPOPT(*LVL2) DBGVIEW(*SOURCE)

      // BSL server control program
      //     change spawn to use the same program and pass job name
      //     move accept back to control job from worker
      //     spawn child jobs as connections are accepted
      //     monitor control dataq
      //     HBSCNTR###

      //**********************************************************
      //  Copyright 1988-2019 by:                                *
      //                    JACK HENRY & ASSOCIATES, INC.        *
      //                    MONETT, MISSOURI  65708              *
      //**********************************************************



sasn  */include qcpysrc,yajl_H

sasn  /include qcpysrc,noxdb

23004 /define HBSTOOLS_psds
      /include qcpysrc,hbstools
23004 /undefine HBSTOOLS_psds

24001  // dcl-f jhcldr     disk usage(*input ) Keyed usropn;
23001  dcl-f HBSFSCHED keyed usage(*update) usropn;

     D HBSCONTROL      pr                  extpgm('HBSCONTROL')
     D                                3
     D HBSCONTROL      pi
     D  bankno                        3

     D AF_INET         c                   const(2)
     D SCK_STREAM      c                   const(1)
     D SOL_socket      c                   const(-1)
     D REUSEADDR       c                   const(55)
     D INADDR_ANY      c                   const(0)
     D INADD_NONE      c                   const(-1)
     D AF_UNIX         c                   const(1)
     D SOCK_DGRAM      c                   const(2)
     d SPAWN_SETJOBNAMEPARENT_NP...
     d                 c                   const(128)                           0x00000080
     d SPAWN_SETJOBNAMEARGV_NP...
     d                 c                   const(256)                           0x00000100

     D*$$errno         pr              *   extproc('__errno')
     D*errno           s             10i 0 based(perrno)

       // Delay process
     D delay           pr            10i 0 extProc('sleep')
     D                               10u 0 value
      * JHSLDA set LDA -----------------------------------------------
     D JHSLDA          pr                  extpgm('JHSLDA')


      // The inet_addr function takes an IP address in dotted
      // decimal format (eg, 192.168.12.1) and converts it
      // to a 32-bit int.
      // NOTE: The IPAddress string must be null-terminated

     D inet_addr       pr            10i 0 extproc('inet_addr')
     D   ipaddress                   16

      // The socket function returns the socket descriptor you'll
      // pass to other functions.
     D socket          pr            10i 0 extproc('socket')
     D   addrfamily                  10i 0 value
     D   commtype                    10i 0 value
     D   protocol                    10i 0 value

      // The socket pair function returns a pair of socket descriptors you'll
      // pass to other functions.
     D socketpair      pr            10i 0 extproc('socketpair')
     D   addrfamily                  10i 0 value
     D   commtype                    10i 0 value
     D   protocol                    10i 0 value
     D   socketvec                     *   value

      // The SetSockOpt function returns a -1 if unsuccessful.
     D setsockopt      pr            10i 0 extproc('setsockopt')
     D   socketdesc                  10i 0 value
     D   level                       10i 0 value
     D   optionname                  10i 0 value
     D   optionvalu                    *   value
     D   optionlen                   10i 0 value

      // The Bind function returns a -1 if unsuccessful.
     D bind            pr            10i 0 extproc('bind')
     D   socketdesc                  10i 0 value
     D   sockaddrss                    *   value
     D   addresslen                  10i 0 value

      // The Listen function returns a -1 if unsuccessful.
     D listen          pr            10i 0 extproc('listen')
     D   socketdesc                  10i 0 value
     D   queuesize                   10i 0 value

      // The Sendmsg function returns a -1 if unsuccessful.
     D sendmsg         pr            10i 0 extproc('sendmsg')
     D   socketdesc                  10i 0 value
     D   msghdr                        *   value
     D   flags                       10i 0 value

     D close           pr            10i 0 extproc('close')
     D   socketdesc                  10i 0 value

      // Prototype cleanup procedure.
     D cleanup         pr
     D   Info                          *

      // Prototype error check procedure.
     D errcheck        pr
     D   result                      10i 0

      // Prototype to submit recv worker jobs for $ort
     D RecvJobs        pr            10i 0
     D   Port#                        5  0
     D   Worker#                      3  0
     D   PortIdx                      3  0

      // Prototype to submit recv worker jobs for port
     D CrtLstn         pr            10i 0
     D   Port#                        5  0

      // Prototype to create listen
     D CrtListen       pr            10i 0

      // Prototype to create listen by individual port
     D CrtListenP      pr            10i 0
     D   Port#                        5  0

M01  dspawnp           pr            10i 0 ExtProc('spawnp')
M01  d path                            *   Value Options(*String)
M01  d fd_count                      10i 0 Value
M01  d fd_map                        10i 0 Dim(256) Options(*VarSize:*Omit)
M01  d inherit                             LikeDS(inheritance_t)
M01  d argv                            *   Dim(256) Options(*VarSize)
M01  d envp                            *   Dim(256) Options(*VarSize)
     d  childParm      ds                  Qualified
     d   id                          10a
23002d   SSLSEC                       1a
23002d   APPID                       50a
     d                                1    Inz(x'00')
        // Local Variables
      // Prototype to submit query handler jobs
     D SbmHandler      pr            10i 0
     D   Worker#                      3  0
      // Prototype to submit push jobs
     D SbmPush         pr            10i 0
     D   Worker#                      3  0
      * Check Controler queue
     D CheckQue        pr            10i 0
     D   p_dtaqnm                    10a   const

      // Prototype to submit query handler jobs
     D EndHandler      pr            10i 0
     D EndPush         pr            10i 0
     D EndRecv         pr            10i 0
     D EndController   pr            10i 0
       dcl-pr HandleCtrlCmd end-pr;

     D SndDtaqkey      pr                  extpgm('QSNDDTAQ')
     D  Qname                        10a   const
     D  Qlib                         10a   const
     D  Qlen                          5  0
     D  Qdata                        10
     D  Qkeylen                       3  0
     D  Qkeydata                     10


23001  dcl-pr CheckCldr ind end-pr;
                                                                                                `
     D pcleanup        s               *   procptr    inz(%paddr('CLEANUP'))
                                                                                                `

      // Receive from the data queue
     D*SndDtaq         pr                  extpgm('QSNDDTAQ')
     D* Qname                        10a   const
     D* Qlib                         10a   const
     D* Qlen                          5  0
     D* Qdata                        10
     D* Qkeylen                       3  0
     D* Qkeydata                     10

      // QCMDEXC to run commands.
     D cmdexc          pr                  extpgm('QCMDEXC')
     D                              512
     D                               15  5

      //

M06   * The FCntl function returns a -1 if unsuccessful.
M06  D fcntl           pr            10i 0 extproc('fcntl')
M06  D                               10i 0 value
M06  D   F_SETFL                     10i 0 value
M06  D   O_NONBLOCK                  10i 0 value options(*nopass)
M06
     d Job_ASP         pr            10a   extproc('JOB_ASP')

     D*uSleep          pr            10i 0 extproc('usleep')
     D*                              10u 0 value

       dcl-pr CEERTX extproc('CEERTX');
         exitProc  pointer(*proc) const;
         userToken char(12) options(*omit);
         fc        char(12) options(*omit);
       end-pr;

     D*system          pr            10i 0 extproc('system')
     D*                                *   value options(*string)
     D accept          pr            10i 0 extproc('accept')
     D   socketdesc                  10i 0 value
     D   sockaddrss                    *   value
     D   addresslen                  10i 0
     D RcvDtaqKey      pr                  extpgm('QRCVDTAQ')
     D                               10a   const
     D                               10a   const
     D                                5  0
     D                               10a
     D                                5  0 const
     D                                2a   const
     D                                3  0 const
     D                               10a   const
     D                                3  0 const
     D                               10a   const
     D                               10a   Const
     D                                5  0 Const
     D                               10a   Const

       dcl-pr GetParms end-pr;
       dcl-pr WrtDtaq ind;
         w_dtaq char(10) const;
       END-PR;



M03    dcl-pr HBSSBSDTA Extpgm('HBSSBSDTA');
24001  //pRunLib char(10) const;
M03    pBankNo char(3) const;
M03    end-pr;


23003  Dcl-Pr ClearDtaQ                ExtPgm('QCLRDTAQ');
23003   DtaqName      char(10)         Const;
23003   DtaqLib       Char(10)         Const;
23003  End-Pr;

       //  dcl-pr RcvDtaq Extpgm('QRCVDTAQ');
       //    qname char(10) const;
        //  qlib char(10) const;
       //  qrcvlen packed(5);
       //  qrcvdta char(10);
       //  qwait packed(5) const;
       //  END-PR;
23001  dcl-s ProcDate ind;
       dcl-s o_nonblock int(10) inz(128);
       dcl-s f_setfl int(10) inz(7);
       dcl-c F_GETFL const(6);
23003  dcl-c dlyw const('DLYJOB DLY(10)');
       dcl-c cSchedIntv const(5);           // Scheduler check interval in seconds
       // FCNTL to set non blocking returns -1 if unsuccessful


      // The standard structure for a sockets address.
     D sockaddr        ds
     D   family                       5i 0 inz(AF_INET)
     D   port                         5u 0
     D   address                     10u 0 inz(INADDR_ANY)
     D   zero                         8    inz(x'0000000000000000')

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
     D   msg_accr                      *   inz(%addr(sockaccept))
     D   msg_accrl                   10i 0 inz(%size(sockaccept))

     D iovec           ds
     D   qdatap                        *   inz(%addr(qdata))
     D   qdatalen                    10i 0 inz(100)

     d inherit         ds                  LikeDS(inheritance_t)
        // Child Spawn
M01  d inheritance_t   ds                  Qualified Template Align
     D   flags                       10u 0 inz(0)
     D   pGroup                      10i 0 inz(0)
     D   sigMask                     20u 0 inz(0)
     D   sigDefault                  20u 0 inz(0)


     D @plinger        s               *
     D  MyLinger       ds                  based(@plinger)
     D   L_onoff                     10i 0
     D   L_linger                    10i 0
     D @ling           s               *
     D len             s             10i 0


     D outds           ds          5000
     D   outkcinfo                  160
     D   outbuffer                 4096

     d g_JHAPAR_Rec  e ds                  extname(JHAPAR) dtaara(JHAPAR)
     d                                     qualified


      //
23001D curdate         s              8  0
23001D date7           s              7  0
23001D JHeod           s             10    dtaara(JHEOD)
     D svec            s             10i 0 dim(2) inz(-1)
     D ser             s             10i 0 dim(2)
     D argv            s               *   dim(3)
     D envp            s               *   dim(1)
     D fdmap           s             10i 0 dim(2)
     D job             s              3  0 dim(2)
     D socklist        s             10i 0 dim(8) inz(-1)
     D rcvport         s              5  0 dim(8)
     D totrecv         s              5  0 dim(8)
     D tothandl        s              5  0 dim(8)
     D jobnhandl       s             10    dim(999)
     D jobnpush        s             10    dim(999)
     D port#           s              5  0
     D bank            s              3  0

sas    dcl-ds dsConfigParms qualified;
         SBS_Name char(10) inz('');
         SBS_Libl char(10) inz('');
         POOLID char(10) inz('');
         POOLSIZ char(10) inz('');
         ACTLVL char(10) inz('');
         SBS_User char(10) inz('');
         SBS_PushJobs int(10) inz(0);
         SBS_ConfigLibl char(10) inz('');
         SBS_LocalIP char(15) inz('');
       end-ds;

sas    dcl-ds dsBankParms qualified;
         Bank_Num int(10) inz(0);
         Bank_FI_ int(10) inz(0); //Bank_FI#
         Bank_User char(10) inz('');
         Bank_DatLib char(10) inz('');
         Bank_Handler_Num int(10) inz(0);
         Bank_Push_Num int(10) inz(0);
         num_Bank_Port_List int(10);
         dcl-ds Bank_Port_List dim(10);
           Bank_Port    int(10) inz(0);
           Bank_SSLTLS  char(1)  inz('');
           Bank_APPID   char(50) inz('');
         end-ds;
         num_Bank_Libl_List int(10);
         dcl-ds Bank_Libl_List dim(30);
           Bank_lib char(10) inz('');
         end-ds;
       end-ds;

      //---------------------------------------------------------------------
      // Stand Alone Fields - TOP
      //---------------------------------------------------------------------
     d  fd_count       s             10i 0 inz(1)
     D BankParm        s             20a
     D w_dta           s             10a
     D w_dta30         s             30a
     D w_QDATA2        s             46a
     D portinto        s              5a
     D HBSCNTRdtq      s             10a
     D HBSDTAQ         s             10a
     D HBSSDTAQ        s             10a
     D HBSRDTAQ        s             10a
     D ServerLibrary   s             10a
     D WorkerName      s             10
     d  jobn           s             10a
     D qcmd            s            512
     D qcmdln          s             15  5
23001D SystemDte       s               z
23001D Systemtme       s              6s 0
23001D StartRange      s               z
23001D EndRange        s               z
     D asp_name        s             10
     D asp_spawn       s             10
     D rstime          s               z
     D retime          s               z
23001D LastSchedRun     s              z   inz(*loval)
     D mcsc            s              9s 0
     D cmpms           s              9s 0 inz(500)
     D resulta         s             10a
     D resultb         s             10a
     D buffer          s           4096
     D bufferlen       s             10i 0
     D rc              s             10i 0
     D count           s              3  0 inz(0)
     D countc          s              3  0 inz(0)
     D countc3         s              3
     D flags           s             10i 0 inz(0)
     D hbserverw       s             10
     D hbserverwl      s             10
     D Qdlen           s              5  0
     D headerlen       s              5  0 inz(160)
     D backlog         s              4  0 inz(512)
     D backloga        s              4
     D solng           s              3  0 inz(000)
     D solnga          s              3
     D hour            s              2  0 inz(0)
     D i               s              3  0 inz(0)
     D j               s             10i 0
     D jobid           s             16
     D pcount          s              2  0 inz(0)
      //
     D lensckadin      s             10i 0 inz(%size(sockaddrin))
     D localtime       s              6  0
     D LogTime         s               z
     D null            s              1    inz(x'00')
     D on              s             10i 0 inz(1)
     D p               s              4  0 inz(0)
     D p2              s              4  0 inz(0)
     D p3              s              4  0 inz(0)
     D path            s             55
     D pid1            s             10i 0
     D pid2            s             10i 0
     D psave           s              4  0 inz(0)
     D qdata           s            100
     D result          s             10i 0
     D sockaccept      s             10i 0 inz(-1)
     D socklisten      s             10i 0 inz(-1)
     D successful      s              1    inz('N')
     D tic             c                   x'7D'
     D workersd        s             11
     D workersdi       s             10i 0
     D workersdi2      s             10i 0
     D x               s             10  0 inz(1)
     D y               s             10  0 inz(0)
     D pos             s              5  0
     D child#          s              3  0
     D totports        s              3  0
     D tothand         s              3  0
     D totpush         s              3  0
     D totspawn        s              5  0
     D push#           s              3  0
     D hand#           s              3  0
     d cError          s             10i 0
     D PAREN           s              1
     D banklibl        s           2000
     D S_dtaqnm        s             10a
M03  D S_dtaqlib       s             10a
     D w_dtaqnm        s             10a
M03  D w_dtaqlib       s             10a
     D dtaqname        s             10a   inz('HBSCNTR')
M03  D dtaqlib         s             10a
24001 //D w_runlib        s             10a
     D wwOpt           s             10i 0
     D IPPROTO_TCP     C                   CONST(6)
     D IPPROTO_IP      C                   CONST(0)
     D TCP_NODELAY     C                   10
     D gInbound        s             10a
       //YAJL work fields
          dcl-s wwFlags uns(10);
sasn   //dcl-s docnode like(yajl_val);
sasn   //dcl-s node like(yajl_val);
sasn   //dcl-s ActvtyTrck like(yajl_val);
       dcl-s ary_p  int(10);                      // Array index for all ports
       dcl-s ary_l  int(10);                      // Array index for library list
       dcl-s w_index  int(10);                      // Array index for all ports
       dcl-s w_indx   int(10);                      // Array index for all ports
       dcl-s a_port   char(5);                      // Alpha port number
       dcl-c incoming const('HBSRCVQ');
       dcl-c cEndh const('"HandlerPgm_Action":"ENDHANDLER"');
       dcl-c cEndp const('"SendPgm_Action":"ENDPUSH"');
       dcl-c cEnd  const('ENDJOB');
       dcl-s w_guid char(36);
       dcl-s w_guid2 char(36);
       dcl-s w_cmd char(256);
       dcl-s w_cmdln packed(15:5);
      //---------------------------------------------------------------------
      // Stand Alone Fields - HBSBS parm fields
      //---------------------------------------------------------------------
     D chglibl         s            512
     D d_push#         s              3 00
     D d_hand#         s              3 00
     D d_jobname       s             10
     D d_clntnam2      s             10
     D* d_sbsname       s             10
     D d_sbslibl       s             10
     D d_cfglibl       s             10
     D d_userid        s             10
     D d_liblst2       s            110
     D d_portlst2      s            116
sas    dcl-s idx1 int(10);
sasn   dcl-s JsonPtr pointer;
      //---------------------------------------------------------------------
      // Stand Alone Fields - BOTTOM
      //---------------------------------------------------------------------
      //---------------------------------------------------------
      // Data Structures
      //---------------------------------------------------------



       dcl-ds aBnklibl dim(2000) qualified;
         l_banklib char(10);
       end-ds;

       dcl-ds aBnkPorts dim(1000) qualified;
         p_portnum packed(5);
23002    p_SSLTLS  char(1);
23002    p_Appid   char(50);
       END-DS;


M03    dcl-ds HBSSBSCTL dtaara(*usrctl);
M03      d_SBSName char(10);
M03      d_SBSLib char(10);
M03      d_BankLib char(10);
M03      d_FINum char(4);
M03      d_LocalIP char(16);
24001    d_CoreID  char(5);
24001    d_Misc    char(445);
M03    end-ds;


      // Register the condition handler to ignore messages.
       // Make sure qdata initialized.
       // Since buffer isn't passed setting qdata to 1 blank and null.
       clear qdata;
       qdata = ' '   + null;
       //
       // CREATE LISTEN SOCKET FOR ALL PORTS SET FOR THE BANK
         CrtListen  ();
       //
       s_dtaqnm = w_dtaqnm;
       s_dtaqlib = W_dtaqlib;
       dow *inlr = *off;

              // usleep(0100000);
         //****************************************************************
         // Accept a connection from the listen backlog and spawn worker
         // Server passing the accepted connection.  Go back to accept
         // to see if another connecition comes in.
         // ** if multiple ports will need to set the listen as non blocking
         // and continually check each port for a connection waiting
         //****************************************************************

M02      I = 1;
         child# = 1;
         For I by 1 to totports;


         if rcvport(I) <> 99999;
         //

         // Read through dataq written by child jobs
         // get total active by port
         // this number will determine how many handlers to submit
         // one handler per x worker jobs
         //If totspawn > 50;
         //  *inlr = *on;
         //endif;
            // check total job by port if greater then max skip
            // accept and creating more recv jobs per socket
            sockAccept  =  accept(sockList(I):
                                  %addr(sockaddrin):
                                  LenSckAdIn);
M02         ErrCheck(sockaccept);
            If sockaccept > 0;                    // connection accepted
               // spawn one child job for each accepted connection
               RecvJobs (rcvport(I) :Child# :I);
               result = close(sockaccept);
            endif;
           endif;
         Endfor;

          usleep(0100000);

         // read dataq to see if any requests for controller to handle
         // determine whether to end handler or push or start a handler or push
         // or end the whole control job read only q entries that match the control
         // job name

         CheckQue(w_dtaqnm);
         HandleCtrlCmd();


23001    // check scheduler for any jobs - throttled to cSchedIntv seconds
23001    if %diff(%timestamp():LastSchedRun:*seconds) >= cSchedIntv;
23001      result = Scheduler();
23001      LastSchedRun = %timestamp();
23001    endif;

       enddo;

       // EndController() handles socket close, EndPush, EndHandler, EndRecv before setting *inlr
       return;

       //--------------------------------------------------------\
       // Do all the start up stuff.                             |
       //--------------------------------------------------------/

       begsr *inzsr;


         // Enable the clean up procedure.  When the program gets
         // cancelled procedure CleanUp will be called.
         CEERTX(pcleanup : *omit : *omit);

         Exec SQL
           Set Option
              commit = *none,
              CloSqlCsr = *endmod,
              Datfmt = *iso;

         // port and  procedure CleanUp will be called.
         // port = 03020;
         child# = 1;
         asp_name = Job_ASP();
         if asp_name <> '**ERROR**' and asp_name <>'*SYSBAS' and
            asp_name <> *blanks;
           asp_spawn = asp_name;
         else;
         asp_spawn = *blanks;
         endif;
       // get launch parms and fi control parms
          GetParms();


       // Set library list from bank lib list using list from getparms
       // do a chglibl on lib list array from getparms
          pos+=1;
           w_indx = 1;
            For w_indx by 1 to ary_l;
              %subst(banklibl : pos: 10) = abnklibl(w_indx).l_banklib;
           pos+=11;
            endfor;

         // set bank lib list
            if banklibl <> *blanks;
               Qcmd  =  'CHGLIBL LIBL(' + %TRIMR(banklibl) + ')';
                 system(qcmd);
            Endif;


23001    if not%open(hbsfsched);
23001       open(e) hbsfsched;
23001       if %error;
23001         *inlr = *on;
23001         return;
23001       endif;
23001    endif;

         in g_JHAPAR_Rec;
24001    //w_runlib = g_jhapar_rec.jhprun;
24001    //HBSSBSDTA(w_runlib :bankno);
24001    HBSSBSDTA(bankno);
M03      in HBSSBSCTL;
M03      w_dtaqlib = d_Banklib;
         hbscntrDTQ  = 'HBSCNTR' + %char(g_JHAPAR_Rec.jhbnkn);
                 hbsSdtaq     = 'HBS' + bankno +'SQ01';
      // CHECK IF CONTROL Q EXISTS AND CREATE IT IF IT DOESNT
         // bankno  = %char(g_JHAPAR_Rec.jhbnkn);
         w_dtaqnm = 'HBSCNTR' + BANKNO;
         w_cmd = 'CHKOBJ OBJ(*LIBL/' +
                  %trim(W_Dtaqnm) + ') OBJTYPE(*DTAQ)';
         w_cmdln = %len(%trim(w_cmd));

         If system(w_cmd) <> 0;

            w_cmd = *blanks;
23003     w_cmd = 'CRTDTAQ DTAQ(' + %trim(w_dtaqlib) + '/' +
23003          %trim(w_dtaqnm) + ') MAXLEN(40) TEXT(''BSL    ' +
23003           ' Control Job Data Queue'') '+
23003          'FORCE(*YES) SEQ(*KEYED) KEYLEN(10) AUT(*ALL)';
23003
            w_cmdln = %len(%trim(w_cmd));
            system(w_cmd);
         endif;

           ClearDtaQ(w_dtaqnm:w_dtaqlib);

         jhslda ();

m03       // Make sure Rcv data queue exists if not create it
M03       gInbound = 'HBS' + BANKNO + 'RQ01';
M03       If not hbstools_ChkDtaq(w_dtaqlib:gInbound);
M03         If not hbstools_CrtDtaq(w_dtaqlib:gInbound:46);
M03            hbstools_Commlog(550010);
M03         endif;
M03       endif;


         w_indx = 1;
         ARY_P  = 1;         // tEST ONLY //
          For w_indx = 1 to totports;
              a_port  = %char(Abnkports(W_indx).P_portnum);
              hbsdtaq = incoming + %subst(a_port:3:3);
              // RecvJobs (Abnkports(W_INDX).p_Portnum:Abnkports(W_INDX).p_Child#);
              SbmHandler(d_hand#);
              SbmPush  (d_push#);
          endfor;

       endsr;

       //--------------------------------------------------------\
       //  Loop through jobs for a prefix and send the listen    |
       //  socket                                                |
       //--------------------------------------------------------/

       begsr SendChild;
         clear outkcinfo;
         outkcinfo = 'AAA' + null;
         qdata = outds;
       // qdata = ' '   + null;
         P3 = 0;
         P2 = 0;
       For P2       by 1 to CHILD#;
               result = sendmsg(ser(p):
                   %addr(msghdr):
                   flags);
               errcheck(result);
               //
               if P3 = 5;
                 usleep(0100000);
                 P3 = 0;
               endif;
               //
       endfor;
       endsr;

       //--------------------------------------------------------\
       //  Error-check procedure                                 |
       //--------------------------------------------------------/
       dcl-proc RecvJobs;
         dcl-pi *n int(10);
           port     packed(5);
           child#   packed(3);
           portIdx  packed(3);
         end-pi;


         argv(*) = *Null;
         envp(*) = *Null;
         inherit = *Allx'00';
         // jobn = 'B540'  + 'R' + x'00';
         jobn = 'B' + bankno + 'R' + %char(port) + x'00';
         // Set Child Parms
         Clear childParm;
         p = portIdx;
         job(p) = Child#;
         pcount +=1;
         // Allocate a socket pair for the worker programs
         result = socketpair(AF_UNIX:
             SOCK_DGRAM:
             0:
             %addr(svec));
         if result < 0;
           //   eval      hbslapierr = 'socketpair'
           //   exsr      LogErr
         Endif;

         ser(p) = svec(1);
         workersdi = svec(2);
         workersdi2 = workersdi + 1;
         workersd = %char(workersdi);
         %subst(workersd : 11 : 1) = x'00';

                 WorkerName  = 'B' + bankno + 'R'
                       +  %char(port);

         inherit.flags = SPAWN_SETJOBNAMEARGV_NP;
         argv(1) = %addr(jobn);
         // argv(1) = %addr(null);
         // Set Child Parms
         Clear childParm;
         childParm.id    = %editc(workersdi:'X');
23002    childParm.SSLSEC = abnkports(portIdx).p_ssltls;
23002    childParm.APPID  = abnkports(portIdx).p_appid;
         // argv(2) = %addr(workersd);
         argv(2) = %addr(childParm);

         // Spawn off the childern
               For cOUNTC = 1 to CHILD#;

                 eval      countc3 = %char(pcount);
               //  WorkerName  = 'BR' + '541'
               //        + countc3;
                 WorkerName  = 'B' + bankno + 'R'
                       +  %char(port);

           // Build path for the spawn
                 ServerLibrary = d_sbslibl;

           clear path;
           if asp_spawn  <>  *blanks;
             path =  %trim(asp_name)   +
                 '/QSYS.LIB/' + %trim(ServerLibrary)
                 + '.LIB/' + 'HBSCHILD1'
                 + '.PGM' + x'00';
           else;
             path = '/QSYS.LIB/' + %trim(ServerLibrary)
                 + '.LIB/' + 'HBSCHILD1'
                 + '.PGM' + x'00';
           Endif;
           fdmap(1) = socklisten;
         pid2 = spawnp(path : fd_count : *Omit : inherit :
                       argv : envp);
           errcheck(pid2);
          // pid2 = spawn(%addr(path):
           //    (workersdi2):
           //    *null:
           //    inherit  :
           //    %addr(argv):
           //    %addr(envp));
           if pid2   < 0;
             hbstools_CommLog(600008:'Error in spawn');
           Endif;

           totrecv(I)  +=1;
         endfor;

         result = close(workersdi);
         if result < 0;
         Endif;


       //
       //  send the listen socket to the child jobs
       //
       usleep(0100000);
       //   sendchild;
         clear outkcinfo;
         outkcinfo = 'AAA' + null;
         qdata = outds;
       // qdata = ' '   + null;
         P3 = 0;
         P2 = 0;
       For P2       by 1 to CHILD#;
               result = sendmsg(ser(p):
                   %addr(msghdr):
                   flags);
               errcheck(result);
               //
               if P3 = 5;
                 usleep(0100000);
                 P3 = 0;
               endif;
               //
       endfor;

        //Close svec(1) and svec2 here
         result = close(svec(1));
         if result < 0;
           // hbslapierr = 'closewkdsi';
           // exsr LogErr;
         Endif;

        //Execute handler jobs - min one per port - pass recieve port
        //one to number of handler jobs

       return rc;
       end-proc;

       dcl-proc CrtListen export;
         dcl-pi *n int(10) end-pi;

         // port and  procedure CleanUp will be called.
         asp_name = Job_ASP();
         if asp_name <> '**ERROR**' and asp_name <>'*SYSBAS' and
            asp_name <> *blanks;
           asp_spawn = asp_name;
         else;
         asp_spawn = *blanks;
         endif;

         // loop through the port array and create a listen for each port per bank
      // Allocate a socket.
           I = 1;
            For I by 1 to totports;
              PORT = RCVPORT(i);
               sockList(I) = socket(AF_INET:
             SCK_STREAM:
             0);
            if result < 0;
              // hbslapierr = 'SocketLstn';
              // exsr LogErr;
            Endif;

         // Set the socket so it will reuse the same local address
         // for each connection.
         result = setsockopt(sockList(I):
             SOL_socket:
             REUSEADDR:
             %addr(on):
             %size(on));
         if result < 0;
           // hbslapierr = 'SetSockopt';
           //    log commerror
         Endif;

         // Disable Nagle's Algorithm
         wwOpt = 1;
         rc = setsockopt(SockList(I)
                        : SOL_socket
                        : TCP_NODELAY
                        : %addr(wwOpt)
                        : %size(wwOpt));
         // Set the local address for the socket and listen.
         result = bind(sockList(I):
             %addr(sockaddr):
             %size(sockaddr));
         if result < 0;
            // eval      hbslapierr = 'Bind :Lstn';
         Endif;

         result = listen(SockList(I): 512);
         if result < 0;
            //  EVal      hbslapierr = 'Listen:bck';
         Endif;

M02         Result = fcntl(socklist(i):
M02                    F_SETFL :
M02                    O_NONBLOCK);

        ENDFOR;
       return rc;
       end-proc;


       dcl-proc CrtListenP export;
         dcl-pi *n int(10);
           port  packed(5);
         end-pi;

         // loop through the port array and create a listen for each port per bank
      // Allocate a socket.
           totports +=1;
           i = totports;
           RCVPORT(I) = PORT;
               sockList(I) = socket(AF_INET:
             SCK_STREAM:
             0);
            if result < 0;
              // hbslapierr = 'SocketLstn';
              // exsr LogErr;
            Endif;

         // Set the socket so it will reuse the same local address
         // for each connection.
         result = setsockopt(sockList(I):
             SOL_socket:
             REUSEADDR:
             %addr(on):
             %size(on));
         if result < 0;
           // hbslapierr = 'SetSockopt';
           //    log commerror
         Endif;

        //  Set the local address for the socket and listen
         result = bind(sockList(I):
             %addr(sockaddr):
             %size(sockaddr));
         if result < 0;
            // eval      hbslapierr = 'Bind :Lstn';
         Endif;

         result = listen(SockList(I): 512);
         if result < 0;
            //  EVal      hbslapierr = 'Listen:bck';
         Endif;
M02         Result = fcntl(socklist(i):
M02                    F_SETFL :
M02                    O_NONBLOCK);

       // wwFlags = wwFlags + O_NONBLOCK;
       // fcntl(socklist(I): F_SETFL: wwFlags);


       return rc;
       end-proc;
       //--------------------------------------------------------\
       //  Error-check procedure                                 |
       //--------------------------------------------------------/
       dcl-proc errcheck;
         dcl-pi *n;
           result  int(10);
         end-pi;

       if result < 0;
         perrno = $$errno;
       endif;

       return;
       end-proc;


23001
23001  //--------------------------------------------------------\
23001  //  Check Scheduler                                       |
23001  //--------------------------------------------------------/
23001  dcl-proc Scheduler export;
23001    dcl-pi *n int(10) end-pi;
23001
23001  SystemDte = %timestamp();
23001  Monitor;
23001    // read through scheduler for bank and determine if
23001    // anything ready to submit
23001          Systemtme = %int(%char(%time:*hms0)) ;
23001          setll  (g_JHAPAR_Rec.jhbnkn) rHBSFSCHED;
23001          reade(e) (g_JHAPAR_Rec.jhbnkn) rHBSFSCHED;
23001          dow  not %eof(HBSFSCHED);
23001
23001           if  bsstatus = 'A';
23001            if BSexpdte <= Systemdte
23001              and %char(BSexpdte) <> '1900-01-01-00.00.00.000000';
23001                reade (g_jhapar_rec.jhbnkn) rHBSFSCHED;
23001                iter;
23001            Endif ;
23001
23001           //  check if schedule expired
23001           if BSNextDte <= SystemDte
23001              and %char(BSNextdte) <> '1900-01-01-00.00.00.000000';
23001
23001             If BSSTRTRUN > 0 and  BSENDTRUN > BSSTRTRUN;
23001               If systemtme < BSSTRTRUN  and systemtme < BSENDTRUN;
23001               Else;
23001                reade(e) (g_jhapar_rec.jhbnkn) rHBSFSCHED;
23001                iter;
23001               endif;
23001             endif;
23001
23001               //Check EOD
23001            if BSRUNEOD = 'N';
23001              in jheod;
vev01        //    If jheod <> 'READY';     // EOD running..check rest of sched file
vev01        // EOD running..check rest of sched file
vev01              If (d_coreid = 'SLK' and jheod <> 'READY')
vev01                  or (d_coreid = '20/20' and jheod <> ' ');
23001                reade (g_jhapar_rec.jhbnkn) rHBSFSCHED;
23001                iter;
23001              Endif ;
23001            Endif ;
23001
23001        // check if we want to run on a processing day only
23001        // If the job is ready to run and bsrunprc = 'Y'
23001        // Check jhcldr if today is processing day
23001        // If today not processing day.. set nextday one day forward to check
23001        // tomorrow and read next rec in sched
23001        // chain to jhcldr with 7 digit julian yyyyddd format of bsnextdte
23001          If BSRUNPRC = 'Y';
23001             If Not checkcldr();
23001               bsnextdte = bsnextdte + %hours(24);
23001               // if bsnextdte < systemdte add 24 hours tosystem dte to
23001               // bring it up to date
23001               If bsnextdte < systemdte;
23001                  bsnextdte = systemdte + %hours(24);
23001               endif;
23001               update rhbsfsched;
23001               reade (g_jhapar_rec.jhbnkn) rHBSFSCHED;
23001               iter;
23001             endif;
23001          endif;
23001
23001
23001            if BSUSER = *blanks;
23001              BSUSER = D_USERID;
23001            endif;
23001
23001            clear d_jobname;
23001            d_jobname   = 'B' + bankno + 'S' + BSEVENT;
23001              QCMD = *BLANKS;
23001                 Qcmd = 'SBMJOB CMD(' +
23001                 BSJCMD
23001               +   ') '
23001               + ' JOB(' + d_jobname + ')'
                    + ' JOBQ(' + %trim(d_cfglibl) + '/' + D_SBSNAME + ')'
23001               + ' OUTQ(*USRPRF)'
23001               + ' USER(' + BSUser + ')'
23001               + ' MSGQ(*USRPRF)';
23001
23001
23001               system(qcmd);
23001
23001        // check if logging turned on and log job submitted and time
23001        If BSLOGRUN = 'Y';
23001           // BSLLOG();
23001        endif;
23001
23001        Select;
23001          when BSFREQ = 'T';     //minutes add minutes to today
23001           bsnextdte = bsnextdte + %minutes(BSMinute);
23001
23001          when BSFREQ = 'H';     // hourly add 60 minutes
23001           bsnextdte = bsnextdte + %minutes(60);
23001
23001          when BSFREQ = 'D';     // daily add one day
23001           bsnextdte = bsnextdte + %hours(24);
23001
23001          when BSFREQ = 'W';     // weekly
23001           bsnextdte = bsnextdte + %days(7);
23001
23001          when BSFREQ = 'B';     // bi weekly
23001           bsnextdte = bsnextdte + %days(14);
23001
23001          when BSFREQ = 'M';     // monthly
23001           bsnextdte = bsnextdte + %months(1);
23001
23001          other;
23001           bsnextdte = systemdte;
23001
23001     endsl;
23001
23001     // update the lastsch and nextsch dates in hbschedf
23001     // if bsnextdte is still less then system date - move system date to bsnextdte
23001     // this will bring the date forward if bsnextdte is multiple frequencies in the past
23001        bslastrun = systemdte;
23001        If bsnextdte < systemdte;
23001        Select;
23001          when BSFREQ = 'T';     //minutes add minutes to today
23001           bsnextdte = systemdte + %minutes(BSMinute);
23001
23001          when BSFREQ = 'H';     // hourly add 60 minutes
23001           bsnextdte = systemdte + %minutes(60);
23001
23001          when BSFREQ = 'D';     // daily add one day
23001           bsnextdte = systemdte + %hours(24);
23001
23001          when BSFREQ = 'W';     // weekly
23001           bsnextdte = systemdte + %days(7);
23001
23001          when BSFREQ = 'B';     // bi weekly
23001           bsnextdte = systemdte + %days(14);
23001
23001          when BSFREQ = 'M';     // monthly
23001           bsnextdte = bsnextdte + %months(1);
23001                  bsnextdte = systemdte + %hours(24);
23001        endsl;
23001        endif;
23001
23001        update rhbsfsched;
23001
23001     Endif;    // bankno and active status
23001     Endif;    // bankno and active status
23001     reade(e) (g_jhapar_rec.jhbnkn) rHBSFSCHED;
23001
23001    EndDo;
23001
23001
23001  on-error;
23001  return -1;
23001
23001  endmon;
23001
23001  return 0;
23001  end-proc;
23001

      //--------------------------------------------------------\
      //  Clean up procedure.                                   |
      //--------------------------------------------------------/
       dcl-proc cleanup;
         dcl-pi *n;
           info  pointer;
         end-pi;

            //  end jobs under control??
      // add code to write to  hbscomlog
23003        hbstools_CommLog(600000:'Control Program Ending Abnormally');

23003  // loop through and end listen sockets
23003    I = 1;
23003    For I by 1 to totports;
23003      result = close(socklist(I));
23003      errcheck(result);
23003   endfor;

       *inlr = *on;
       return;
       end-proc;


      //---------------------------------------------------------
      // sbmHandler - Submit Handler jobs
      //  Submit x number of handler jobs per recieve port
      //---------------------------------------------------------

       dcl-proc SbmHandler export;
         dcl-pi *n int(10);
           worker#  packed(3);
         end-pi;

         // Submit handler jobs
               countc = 0;
               tothand = 0;
               For COUNTC = 1 to worker#;
               tothand +=1;

                 countc3 = %char(countc);
                 // eval      bankno  = %char(g_JHAPAR_Rec.jhbnkn);
                 d_jobname   = 'B' + bankno  +'H'
                       + countc3;
                 hbsrdtaq     = 'HBS' + bankno + 'RQ01';

          QCMD = *BLANKS;
          Qcmd = 'SBMJOB CMD(CALL PGM(HBShandlr)'
          + ' PARM(' + tic   + HBSRDTAQ + tic + ' '
                    +   ')) '
                    + ' JOB(' + d_jobname + ')'
                    + ' JOBQ(' + %trim(d_cfglibl) + '/' + D_SBSNAME + ')'
                    + ' OUTQ(*USRPRF)'
                    + ' USER(' + D_USERID + ')'
                    + ' MSGQ(*USRPRF)';

             jobnhandl(countc) = d_jobname;
                 system(qcmd);

                  //  load jobname array for handler
               endfor;
          return rc;

        end-proc;
      //---------------------------------------------------------
      // SbmPush      Submit Push
      //  Submit x number of Push jobs for a bank
      //           passing the port number
      //           name job  BPSHPPPPP00
      //---------------------------------------------------------

       dcl-proc SbmPush export;
         dcl-pi *n int(10);
           worker#  packed(3);
         end-pi;

         // Submit handler jobs
               countc = 0;
               TOTPUSH = 0;
               For COUNTC = 1 to worker#;
               totpush +=1;

                 countc3 = %char(countc);
                 d_jobname   = 'B' + bankno  +'P'
                       + countc3;
                 hbsdtaq     = 'HBS' + bankno + 'SQ01';

          QCMD = *BLANKS;
          Qcmd = 'SBMJOB CMD(CALL PGM(HBspush) PARM(' + tic   + HBSDTAQ
                    + tic   +   ')) '
                    + ' JOB(' + d_jobname + ')'
                    + ' JOBQ(' + %trim(d_cfglibl) + '/' + D_SBSNAME + ')'
                    + ' OUTQ(*USRPRF)'
                    + ' USER(' + D_USERID + ')'
                    + ' MSGQ(*USRPRF)';


                 system(qcmd);
                  //  load jobname array for push
             jobnpush(countc) = d_jobname;

               endfor;


          return rc;

        end-proc;

      //----------------------------------------------------------
      // GetParms - Retreive JSON Parameter info for parsing
      //----------------------------------------------------------
       dcl-proc GetParms;
        dcl-pi *n end-pi;

       dcl-s PrmClob sqltype(clob:32000);
sas    dcl-s ParmJson varchar(3000);
       dcl-s PrmJSON varchar(32000);

        //YAJL work fields
sasn   //dcl-s docnode like(yajl_val);
       dcl-s b_indx int(10);                      // JSON Node index for bank list
       dcl-s l_indx int(10);                      // JSON Node index for lib list
       dcl-s p_indx int(10);                      // JSON Node index for port list
sasn   //dcl-s LiblTable like(yajl_val);
sasn   //dcl-s PortTable like(yajl_val);
sasn   //dcl-s t_node like(yajl_val);
       dcl-s errmsg varchar(500);
sasn   //dcl-s node like(yajl_val);

       Monitor;
         d_sbsname = *blanks;
         d_sbslibl = *blanks;
         d_userid = *blanks;

        //  Add sql to hbsparc (fi control), hbsparl (subsystem control)

       //  PrmJson = *blanks;
         ParmJson = *blanks;

         Exec SQL
sasps  //    select Hssbsparm into :PrmClob
sasps      select Hssbsparm into :ParmJson
             from hbspars
             where Hssbsparm <> ' ' and hssbsid = 'SBSCONFIG ';

sasps  //  PrmJson = %trim(PrmClob_data);


sasps  //  If prmjson <> *blanks;
sasps    If ParmJson <> *blanks;

sas    //    ParseJson(prmjson: 'CONFIG');
sas        ParseJson(ParmJson: 'CONFIG');

sas!!    // clarify names between sbsconf and the hbssbsctl data area!!!
sas      d_sbsname = dsConfigParms.SBS_Name;
sas      d_sbslibl = dsConfigParms.SBS_Libl;

sas      d_userid = dsConfigParms.SBS_User;

sas      d_cfglibl = dsConfigParms.SBS_ConfigLibl;

         endif;

         If d_userid = *blanks;
           d_userid = '*CURRENT';
         ENDIF;

         If d_sbsname = *blanks;
           d_sbsname  = 'BSLNET   ';
         ENDIF;

         If d_sbslibl = *blanks;
           d_sbslibl  = 'BSLCOM  ';
         ENDIF;

         If d_cfglibl = *blanks;
           d_cfglibl = d_sbslibl;
         endif;

         Bankparm = 'BANK' + bankno;

         Exec SQL
sasps  //    select Hssbsparm    into :PrmClob
sasps      select Hssbsparm    into :ParmJson
             from hbspars
             where hssbsparm <> ' ' and hssbsid = :Bankparm;



sas      ParseJson(ParmJson: 'BANK');

sas      bank = dsBankParms.Bank_Num;
sas    //  bfi = dsBankParms.Bank_FI_;
sas      D_UserID = dsBankParms.Bank_User;
sas    //  bdatlib = dsBankParms.Bank_DatLib;
sas      D_Hand# = dsBankParms.Bank_Handler_Num;
sas      Hand# = dsBankParms.Bank_Handler_Num;
sas      D_Push# = dsBankParms.Bank_Push_Num;
sas      for ary_p = 1 to dsBankParms.num_Bank_Port_List;
sas        AbnkPorts(ary_p).p_portnum =
sas          dsBankParms.Bank_Port_List(ary_p).Bank_Port;
23002      AbnkPorts(ary_p).p_ssltls  =
23002        dsBankParms.Bank_Port_List(ary_p).Bank_SSLTLS;
23002      AbnkPorts(ary_p).p_appid   =
23002        dsBankParms.Bank_Port_List(ary_p).Bank_APPID;
sas        rcvport(ary_p) = AbnkPorts(ary_p).p_portnum;
sas      endfor;
sas      totports = dsBankParms.num_Bank_Port_List;
sas      for ary_l = 1 to dsBankParms.num_Bank_Libl_list;
sas        aBnklibl(ary_l).l_banklib =
sas          dsBankParms.Bank_Libl_List(ary_l).Bank_Lib;
sas      endfor;

         on-error;

                 If d_userid = *blanks;
                   d_userid = '*CURRENT';
                 ENDIF;

                If d_sbsname = *blanks;
                  d_sbsname  = 'BSLNET';
                ENDIF;

               If d_sbslibl = *blanks;
                 d_sbslibl  = 'BSLCOM';
               ENDIF;


         // load defaults into arrays

         endmon;

sas    //  yajl_tree_free(docnode);


         Return;

        end-proc;

      //---------------------------------------------------------
      // WrtDtaq - Write outgoing GUID to Send Data queue
      //---------------------------------------------------------
        dcl-proc WrtDtaq;
          dcl-pi *n ind;
            p_Dtaq char(10) const;
          END-PI;

              %subst(w_qdata2:1:36) = w_guid2;
              %subst(w_qdata2:37:10) = psjobnm;
          qdlen = 46;
m03       SndDtaq(P_dtaq:w_dtaqlib:qdlen:w_QDATA2);

              return *off;

        END-PROC;


23003
23003 *--------------------------------------------------------\
      *  Check Controller queu and react to requests           |
      *--------------------------------------------------------/
       dcl-proc CheckQue;
         dcl-pi *n int(10);
           p_dtaqnm  char(10) const;
         end-pi;

         dcl-s ck_datqnm  char(10) inz(*blanks);
         dcl-s ck_datlib  char(10) inz(*blanks);
         dcl-s w_len      packed(5) inz(10);
         dcl-s w_wait     packed(5) inz(0);
         dcl-s w_keyord   char(2)   inz('NE');
         dcl-s w_keylen   packed(3) inz(10);
         dcl-s w_keydata  char(10)  inz(*blanks);
         dcl-s w_sendlen  packed(3) inz(8);
         dcl-s w_sendinf  char(8)   inz(*blanks);
         dcl-s DataQLen   packed(5) inz(40);

21001    dcl-ds w_ErrDS;
21001      w_prvbyte int(10) pos(1);
21001      w_aftbyte int(10) pos(5);
21001      w_excpID  char(7) pos(9);
21001      w_reserv  char(1) pos(16);
21001    end-ds;


          // change to recieve only entries for B###C job matching the controljob
          // dataq entry should be deleted when received
        monitor;
          w_dta = *blanks;
          qdlen = 10;
          ck_datqnm = p_dtaqnm;
          ck_datlib = W_dtaqlib;
23003      //  RcvDtaq(ck_dtaqnm:w_dtaqlib: qdlen: w_dta: 0);
23003
23003     RcvDtaqKey(ck_datqnm:ck_datlib:qdlen:w_dta30: 0
23003                    : 'EQ' : 10 : psjobnm : 0 :*Blanks
                    : '*NO' : DataqLen : w_ErrDS) ;


       //  RcvDtaQ(DataQNam : DataQLib : DataQLen : DataQValue
       //          : 0 : *Blanks : 0 : *Blanks : 0 :*Blanks
       //           : '*NO' : DataqLen : *Blanks) ;



        on-error;

        Endmon;

        return rc;
       end-proc;

      //---------------------------------------------------------
      // HandleCtrlCmd - Act on command received from CheckQue
      //   Commands are 5-digit codes in w_dta30(1:5);
      //   port number (if applicable) in w_dta30(6:5).
      //---------------------------------------------------------
       dcl-proc HandleCtrlCmd;
         dcl-pi *n end-pi;

         if w_dta30 = *blanks;
           return;
         endif;

         select;
           when %subst(w_dta30:1:5) = '00001';   // End controller — close all listen sockets
             EndController();

           when %subst(w_dta30:1:5) = '00002';   // End listen on one port
             //  only allow if totrecv(I) for the port is already set to 0 ?
             //  only allow if tothandl(I) for the port is already set to 0 ?
             port = %dec(%subst(w_dta30:6:5):5:0);
             I = %lookup(port:rcvport);
             result = close(socklist(I));
             rcvport(I) = 99999;

           when %subst(w_dta30:1:5) = '00003';   // Start listen on one port
             port# = %dec(%subst(w_dta30:6:5):5:0);
             CrtListenP(port#);

           when %subst(w_dta30:1:5) = '20001';   // End one active handler
             // make sure all active receives have ended
             I = %lookup(port:rcvport);
             tothandl = tothandl - 1;
             // TODO: send ENDJOB to specific handler job (job name in w_dta30:6:10)

           when %subst(w_dta30:1:5) = '20002';   // Start one handler
             w_indx = 1;
             SbmHandler(d_hand#);

           when %subst(w_dta30:1:5) = '30001';   // End one push
             // TODO: send ENDJOB to specific push job (job name in w_dta30:6:10)

           when %subst(w_dta30:1:5) = '30002';   // Start one push
             w_indx = 1;
             SbmPush(d_push#);

           when %subst(w_dta30:1:5) = '40001';   // End receive for one port
             port = %dec(%subst(w_dta30:6:5):5:0);
             I = %lookup(port:rcvport);
             totrecv(I) = totrecv(I) - 1;
             //  totrecv(I) tracks number of active workers for the port

         endsl;

         return;
       end-proc;
23001
23001 //---------------------------------------------------------
23001 // CheckCldr  - Check JHCLDR if today is processing day
23001 //---------------------------------------------------------
23001   dcl-proc CheckCldr;
23001     dcl-pi *n ind end-pi;

24001   dcl-s curdate zoned(8);
24001   dcl-s cfyear packed(4);
24001   dcl-s cfdate packed(6);
24001   dcl-s procday char(1);
24001   dcl-s slkdate packed(7);

23001
23001     Procdate = *off;
23001

24001     if d_CoreID = '20/20';
24001       curdate = *date;
24001       cfdate  = %int(%char(%date():*mdy0));
24001       exec sql
24001         select proday
24001         into :procday
24001         from jhcldr
24001         where cdate = :cfdate;
24001     elseif d_CoreID = 'SLK';
24001       curdate = *date;
24001       slkdate  = %int(%char(%date():*longjul0));
24001       exec sql
24001         select proday
24001         into :procday
24001         from jhcldr
24001         where cjdate = :slkdate;
24001     else;
24001       procday = 'N';
24001     endif;
24001
24001     if procday = 'Y';
24001       procdate = *on;
24001     endif;
23001
23001     Return Procdate;
23001   END-PROC;
23003 //---------------------------------------------------------
23003 // EndPush      End Push
23003 //  End    x number of Push jobs for a bank
23003 //           by writing the push job name to the keyed
23003 //           dataq
23003 //---------------------------------------------------------
23003
23003  dcl-proc EndPush;
23003    dcl-pi *n int(10) end-pi;
23003    dcl-s w_len    packed(5) inz(40);
23003    dcl-s w_keylen packed(3) inz(10);
       dcl-s wCtrlReq char(10);
23003
23003    // Create a job name array and end all jobs still in the array
23003    // Loop through 1 to x number of total push jobs
23003    wCtrlReq  = 'ENDJOB';
23003    I = 1;
23003    For I by 1 to totpush;
23003      // If jobname in array is not blanks send a keyed dataq
23003      // entry to tell the push to end
23003       if jobnpush(I) <> *blanks;
23003             //      SndDtaq(S_dtaqnm:S_DTAQLIB:w_len:
23003             //          jobnpush(I):w_keylen:CendP);
23003                     SndDtaq(w_dtaqnm:W_DTAQLIB:w_len:
23003                         wCtrlReq:w_keylen:jobnpush(I));
23003       endif;
23003    Endfor;
            //
            //  also add a send to the push send      q
            //  with a guid of 'CONTROL' to get the push  to look
            //  at the control q for instructions
            //
             usleep(2000000);
23003     w_guid2 = 'CONTROL';
23003     qdlen = 36;
23003    I = 1;
23003    For I by 1 to totpush;
23003     SndDtaq(hbsdtaq:w_dtaqlib:qdlen:w_guid2);
23003     clear w_guid2;
23003    Endfor;
23003       //
23003     return rc;
23003
23003   end-proc;
23003
23003 //---------------------------------------------------------
23003 // EndHandler   End Handler
23003 //  End    x number of handler jobs for a bank
23003 //           by  the handler job name to the dataq
23003 //---------------------------------------------------------
23003
23003  dcl-proc EndHandler;
23003    dcl-pi *n int(10) end-pi;
23003    dcl-s w_len    packed(5) inz(40);
23003    dcl-s w_keylen packed(3) inz(10);
       dcl-s wCtrlReq char(10);
23003
23003    // Submit handler jobs
23003    // Create a job name array and end all jobs still in the array
23003    // Loop through 1 to x number of total push jobs
23003    // Create a job name array and end all jobs still in the array
23003    // Loop through 1 to x number of total push jobs
23003    wCtrlReq = 'ENDJOB  ';
23003    I = 1;
23003    For I by 1 to tothand;
23003      // If jobname in array is not blanks send a keyed dataq
23003      // entry to tell the push to end
23003       if jobnhandl(I) <> *blanks;
21001             //      SndDtaq(w_dtaqnm:W_DTAQLIB:w_len:
23003             //          jobnhandl(I):w_keylen:CendP);
23003                     SndDtaq(w_dtaqnm:W_DTAQLIB:w_len:
23003                         wCtrlReq:w_keylen:jobnhandL(I));
23003       endif;
23003    Endfor;
23003
            //
            //  also add a send to the handlr recieve q
            //  with a guid of 'CONTROL' to get the handler to look
            //  at the control q for instructions
            //
23003    I = 1;
23003
23003    W_QDATA2 = 'CONTROL  ';
23003    I = 1;
23003    For I by 1 to tothand;
23003     SndDtaq(hbsrdtaq:w_dtaqlib:qdlen:w_QDATA2);
23003    Endfor;
23003
23003    clear W_QDATA2;
23003     return rc;
23003
23003   end-proc;
23003
23003 //---------------------------------------------------------
23003 // EndRecv      End Recv
23003 //  End    x number of Recv    jobs for a bank
23003 //           by  the handler job name to the dataq
23003 //---------------------------------------------------------
23003
23003  dcl-proc EndRecv;
23003    dcl-pi *n int(10) end-pi;
23003
23003     dcl-s jobn     char(10);
23003     dcl-s REND     char(10);
23003     dcl-s w_len    packed(5) inz(40);
23003     dcl-s w_keylen packed(3) inz(10);
23003     dcl-s wCtrlReq char(10);
23003    // send totrecv number of dataq entries  to end recieve
23003    // all recieve jobs have the same job name
23003    clear jobn;
23003    wctrlreq = 'ENDJOB';
23003    I = 1;
23003    For I by 1 to totports;
23003      jobn = 'B' + bankno + 'R' + %char(rcvport(I));
23003      For cOUNTC = 1 to totrecv(I);
23003        // Send one ENDJOB signal per worker keyed to its job name
23003                     SndDtaqkey(w_dtaqnm:W_DTAQLIB:w_len:
23003                         wCtrlReq:w_keylen:jobn);
23003      Endfor;
23003    Endfor;
23003
23003     return rc;
23003
23003   end-proc;
23003
23003
23003 //---------------------------------------------------------
23003 // EndController - call all end job procs before ending the
23003 //   controller
23003 //---------------------------------------------------------
23003
23003  dcl-proc EndController;
23003    dcl-pi *n int(10) end-pi;
23003
23003    // End Controller job - end all handler, push, recv, delay a few seconds then end
23003     IF TOTPUSH > 0;
23003       ENDPUSH();
23003     ENDIF;
23003
23003          usleep(1000000);
23003
23003     iF tOTHAND  > 0;
23003       ENDHANDLER();
          ENDIF;
23003
               usleep(1000000);
23003
23003     iF totports > 0;
23003       EndRecv();
          ENDIF;
23003
               usleep(1000000);
23003     // DO REMAINING CLEANUP AND SET ONLR
               usleep(2000000);
23003        hbstools_CommLog(600000:'Control Program Ending Normally');
23003
23003    I = 1;
23003    For I by 1 to totports;
23003      result = close(socklist(I));
23003      errcheck(result);
23003   endfor;
23003
23003  *inlr = *on;
23003     return rc;
23003
23003   end-proc;
23003
23003

sas   //---------------------------------------------------------
      // ParseJSON - Parse JSON string
      //---------------------------------------------------------
       dcl-proc ParseJSON;
         dcl-pi *n;
           pJSON varchar(3000);
           pParmKeyType char(10) const;
         END-PI;

       dcl-s DataIntoOptions varchar(200);
       //dcl-s YajlIntoOptions varchar(200);

sasn   JsonPtr = json_parseString(%trimr(pJson));

       DataIntoOptions = 'doc=string case=convert countprefix= num_  -
         allowextra=yes allowmissing=yes trim=none';

       //YajlIntoOptions = '{ "value_null": ""}';

       select;
       //  when pParmKeyType = 'BANK';
       //    data-into dsBankParms %DATA(pJSON
       //                  : DataIntoOptions)
       //                         %PARSER('YAJLINTO'
       //                         :YajlINtoOptions);
         when pParmKeyType = 'BANK';
           data-into dsBankParms %DATA(''
                         : DataIntoOptions)
                         %PARSER(json_DataInto(JsonPtr));

       //  when pParmKeyType = 'CONFIG';
       //    data-into dsConfigParms %DATA(pJSON
       //                  : DataIntoOptions)
       //                         %PARSER('YAJLINTO'
       //                         :YajlINtoOptions);
         when pParmKeyType = 'CONFIG';
           data-into dsConfigParms %DATA(''
                         : DataIntoOptions)
                                %PARSER(json_DataInto(JsonPtr));
       endsl;

       json_delete(JsonPtr);

         return;

       end-proc;
