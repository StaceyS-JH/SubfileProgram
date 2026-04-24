      // Create command
      *> CRTSQLRPGI OBJ(&O/&ON) SRCFILE(&L/QRPGLESRC) -
      *> OBJTYPE(*PGM) OUTPUT(*NONE) RPGPPOPT(*LVL2) DBGVIEW(*SOURCE)

       Ctl-Opt Option(*SrcStmt: *NODebugIO);
       Ctl-Opt BndDir('JHIGNM':'JHBIND': 'DDBIND');
       Ctl-Opt ActGrp(*Caller);

      // ---------------------------------------------------------//
      //   Copyright 1988-2024 by:  Jack Henry & Associates, Inc. //
      //                         Monett, Missouri  65708          //
      // ---------------------------------------------------------//

26001 // 04/23/26 #xxxxxxx  S Smith - Convert inbound list from hbsrecv/hbssend to hbstrans
24002 // 10/07/24 #1180779  S Smith - V3 Enhancements
24001 // 06/5/24 #1179375  V Everett - expand HBSSBSCTL
23001 // 04/10/23 #1179389 S Smith - Dashboard V2

       dcl-f hbslogx1 keyed usage(*input) usropn;
       Dcl-F hbsdbfm WorkStn IndDS(gInd) sfile(sfla : rrna)
                                         sfile(sflb: rrnb)
                                         sfile(sflc: rrnc)
                                         sfile(sfld: rrnd);
    //    dcl-f hbsversn keyed usage(*input) usropn;

       Dcl-Pr EntryParm ExtPgm('HBSDB');
       End-Pr;

       Dcl-PI EntryParm;
       END-PI;

       dcl-pr HBSViewJSON extpgm('HBSJSV');
         pFile char(10) const;
         pField char(10) const;
         pRef1 char(40) const;
         pRef2 char(40) const;
         pString varchar(2000000) const;
       end-pr;

       dcl-pr HBSParms extpgm('HBSWP');
       end-pr;
       dcl-pr HBSWorkCtlQ extpgm('HBSWCQ');
       end-pr;
       dcl-pr HBSComTest  extpgm('HBSCOMT3');
       end-pr;
       dcl-pr HBSDispDataArea extpgm('HBSDDA');
       end-pr;
       dcl-pr DebugService  extpgm('HBSSRVTSTC');
         pguid char(36) const;
         hostpgm char(10) const;
       end-pr;
24002  dcl-pr HBSSubfileService extpgm('HBSHSS');
24002    pService char(10) const;
24002    pFunction char(1) const;
24002    pInput1 char(50) const;
24002    pInput2 char(50) const;
24002    pInput3 char(50) const;
24002    oValue1 char(50);
24002    oValue2 char(50);
24002    oValue3 char(50);
24002  end-pr;
24002  dcl-s Input1 char(50);
24002  dcl-s Input2 char(50);
24002  dcl-s Input3 char(50);
24002  dcl-s Value1 char(50);
24002  dcl-s Value2 char(50);
24002  dcl-s Value3 char(50);

       // Data Structures -----------------------------------------------------
       Dcl-DS gInd Qualified;
          Functions    Ind Pos(01) Inz(*Off);
          Exit         Ind Pos(03) Inz(*Off);
          Prompt       Ind Pos(04) Inz(*off);
          Refresh      Ind Pos(05) Inz(*off);
          Format       Ind Pos(08) Inz(*off);
          Filter       Ind Pos(09) Inz(*off);
          Swap         Ind Pos(11) Inz(*Off);
          Previous     Ind Pos(12) Inz(*Off);
sas5      ResetReq     Ind Pos(13) Inz(*Off);
          Parameters   Ind Pos(15) Inz(*Off);
          WrkSbs       Ind Pos(16) Inz(*Off);
          TooMany      Ind Pos(30) Inz(*off);
          RecFromDateInvalid Ind Pos(40) Inz(*off);
          RecFromTimeInvalid Ind Pos(41) Inz(*off);
          RecStatusInvalid Ind Pos(42) Inz(*off);
          SndStatusInvalid Ind Pos(43) Inz(*off);
          ServiceInvalid Ind Pos(44) Inz(*off);
          RecToDateInvalid Ind Pos(45) Inz(*off);
          RecToTimeInvalid Ind Pos(46) Inz(*off);
          SflA_Empty    Ind Pos(64) Inz(*Off);
          SflA_Clear    Ind Pos(65) Inz(*Off);
          SflA_End      Ind Pos(66) Inz(*Off);

          SflD_Empty    Ind Pos(67) Inz(*Off);
          SflD_Clear    Ind Pos(68) Inz(*Off);
          SflD_End      Ind Pos(69) Inz(*Off);

          SflB_Empty    Ind Pos(74) Inz(*Off);
          SflB_Clear    Ind Pos(75) Inz(*Off);
          SflB_End      Ind Pos(76) Inz(*Off);

          SflC_Empty    Ind Pos(77) Inz(*Off);
          SflC_Clear    Ind Pos(78) Inz(*Off);
          SflC_End      Ind Pos(79) Inz(*Off);

       End-DS;

       // Copy Books ----------------------------------------------------------
       ///Copy qcpysrc,SYSTEMCPY
       ///Copy qcpysrc,DDMISCUCPY
       /include qcpysrc,yajl_h
       /include qcpysrc,HBSTOOLS
       /copy *libl/qcpysrc,sqlstruct


      // Misc. Field Declarations
       //Dcl-S SndRcv Char(1);
         Dcl-S Build  Ind Inz(*on);
         dcl-s pos1 int(10);
         dcl-s pos2 int(10);
         dcl-s header varchar(500);
         Dcl-S Changed Ind Inz(*on);
         dcl-s s#rrna like(rrna);
         dcl-s s#rrnd like(rrna);
         dcl-s test1 int(10);
         dcl-s test2 int(10);
         dcl-s test3 int(10);
         dcl-s WhereStatement varchar(500);
         dcl-s SQLStatement varchar(2000);
         dcl-c tic x'7D';
         dcl-s RcvDateFrom date;
         dcl-s RcvDateTo date;
         dcl-s SndDateFrom date;
         dcl-s SndDateTo date;
         dcl-s done ind inz(*off);
         dcl-s Exit ind inz(*off);
         dcl-s error ind inz(*off);
         dcl-s SwapDirection ind inz(*off);
         dcl-s rtnvalue char(40) inz(*blanks);
         dcl-s Direction char(1) inz(*blanks);
         dcl-s CmdString varchar(200) inz(*blanks);

       Dcl-S blockSize Int(10) Inz(%Elem($dsHBSRECV));
       Dcl-S Index# Int(10);
       Dcl-S noMoreRows Ind;

25001  Dcl-DS $dsHBSRECV Qualified Dim(999) Inz;
          aguid    char(36);
          pguid    char(36);
          header   varchar(500);
          rcvstat  char(1);
          rcvts    char(26);
       End-DS;

25001  Dcl-DS $dsREC Qualified Dim(999) Inz;
          aguid     char(36);
26001     rpguid    char(36);
26001     raguid    char(36);
          header    char(500);
          rcvstat   char(1);
          rcvts     char(26);
          sndstat   char(1);
          sndts     char(26);
          jsnip     varchar(25);
26001     sname     varchar(40);
26001     pname     char(10);
       End-DS;

25001  Dcl-DS $dsOutREC Qualified Dim(999) Inz;
          aguid     char(36);
          pguid     char(36);
          attmps    int(10);
          sndstat   char(1);
          sservice  char(10);
          response  char(500);
          sndts     char(26);
          type      char(10);
          sheader   char(100);
       End-DS;

       dcl-ds RcvResp qualified;
         Success ind inz(*off);
       end-ds;

26001  dcl-ds dsSF06 qualified;
         aguid    char(36);
         pguid    char(36);
         type     char(10);
         rcvsts   char(1);
         sndsts   char(1);
         attmps   int(10);
         rcvts    char(26);
         sndts    char(26);
         sname    varchar(40);
         pname    char(10);
       end-ds;

       dcl-s d6aguid  char(36);
       dcl-s d6pguid  char(36);
       dcl-s d6type   char(10);
       dcl-s d6rcvsts char(1);
       dcl-s d6sndsts char(1);
       dcl-s d6attmps zoned(3:0);
       dcl-s d6rcvts  char(26);
       dcl-s d6sndts  char(26);
       dcl-s d6sname  char(40);
       dcl-s d6pname  char(10);
26001  dcl-s d6opt    char(2);

24001  dcl-ds dsHBSSBSCTL;
         d_SBSName char(10);
         d_SBSLib char(10);
         d_BankLib char(10);
         d_FINum char(4);
         d_LocalIP char(16);
24001    d_CoreID  char(5);
24001    d_Misc    char(445);
       end-ds;

24002  dcl-s mysqlclobdata sqltype(CLOB:2000000);
24002  dcl-s myclobdata varchar(2000000);
24002  dcl-ds NtQuery qualified;
24002   dcl-ds HeaderInfo;
24002     QueryNum char(16) inz('');
24002   end-ds;
24002  end-ds;


       Exec SQL
         Set Option
            commit = *none,
            CloSqlCsr = *endmod,
            Datfmt = *iso;

       // default to inbound;
       Direction = 'I';
       Init_In();
       dow 1 = 1;
         select;
           when Direction = 'I';
             Show_In();
           when Direction = 'O';
             Show_Out();
         endsl;
         if Exit;
           leave;
         endif;
         if SwapDirection;
           gInd.Functions = *off;
           gInd.Exit = *off;
           gInd.Previous = *off;
           gInd.Swap = *off;
           gInd.Format = *off;
           gInd.Filter = *off;
           gInd.Refresh = *off;
           SwapDirection = *off;
           gInd.Parameters = *off;
           select;
             when Direction = 'I';
               Direction = 'O';
             when Direction = 'O';
               Direction = 'I';
           endsl;
         endif;
       enddo;

       *inlr = *on;

       //----------------------------------------------------------------------
      // Build List
       Dcl-Proc Build_In_List;

         gInd.Sfla_Clear = *On;
         Write sflac;
         gInd.Sfla_Clear = *off;
         gInd.Sfla_Empty = *off;
         crrna = 0;
         rrna = 0;
         blockSize = %Elem($dsREC);
         noMoreRows = *off;

26001    SQLStatement = ' SELECT  HTGUID, ' +
26001      'HTRQPGUID, '                                  +
26001      'HTRQAGUID, '                                  +
           'cast(HTREQHDR as char(500)),'                 +
           'HTRCVSTS, '                                   +
           'cast(HTRCVTS as char(26)), '                  +
           'HTSNDSTS, '                                   +
           'cast(HTSNDTS as char(26)), '                  +
           'cast(' + tic + tic + ' as varchar(25)), '    +
26001      'HTSNAME, '                                    +
26001      'HTPNAME '                                     +
         'From hbstrans '                                +
         'where @W '                                     +
         'Order by '                                     +
         '  HTRCVTS desc '                               +
         'For Read Only';

         SQLStatement = %scanrpl('@W':WhereStatement:SQLStatement);

         Exec SQL Prepare the_Csr from :SQLStatement;
         Exec SQL Declare hbsrecv_Csr Cursor for the_Csr;

         Exec SQL Open hbsrecv_Csr;

         DoU noMoreRows;
           Exec SQL
             Fetch Next From hbsrecv_Csr
             For :blockSize Rows
           Into :$dsREC;

           If sqlState = SQL_EndOfData;
              noMoreRows = *On;
              Leave;
           ElseIf sqlcode <> 0;
              If CheckSQLState(sqlstate) = 'C';
                 MsgHdlr(MessageType: GetSQLCode(sqlcode):MessageFile);
              EndIf;
           EndIf;

           BlockSize = SQL_FetchCount;
           NoMoreRows = SQL_LastRowIndicator = 100;
           For Index# = 1 To BlockSize;
25001          if rrna >= 999;
                 gInd.TooMany = *on;
                 leave;
               endif;
               rrna += 1;
               aguid   = $dsrec(index#).aguid;
26001          pguid   = $dsrec(index#).rpguid;
               header  = $dsrec(index#).header;
26001          service = %trim($dsrec(index#).sname);
26001          HostPgm = $dsrec(index#).pname;

24002          if service = 'NTQuery';
                 mysqlclobdata_data = '';
                 mysqlclobdata_len = 0;

26001            exec sql
26001              select HRBODY into :mysqlclobdata
26001                from HBSREQ
26001                where HRGUID = :aguid;

                 myclobdata = %trim(mysqlclobdata_data);

24002            data-into NTQuery %DATA(myclobdata
24002                    : 'doc=string case=convert countprefix= num_ -
24002                    allowextra=yes allowmissing=yes')
24002                           %PARSER('YAJLINTO');

24002            service = 'NTQuery' + NTQuery.HeaderInfo.QueryNum;
24002          endif;

               rcvstat = $dsrec(index#).rcvstat;
               rcvts   = $dsrec(index#).rcvts;
               sndstat = $dsrec(index#).sndstat;
               sndts   = $dsrec(index#).sndts;

               if %len($dsrec(index#).jsnip) > 1;
                 rcvscs = %subst($dsrec(index#).jsnip:12:1);
               else;
                 rcvscs = ' ';
               endif;
sas            if %subst(header:1:8) = 'INTERNAL';
                 itype = 'I';
               else;
                 itype = ' ';
               endif;
               Write sfla;
           EndFor;
25001    NoMoreRows = *on;
         EndDo;

         Exec Sql Close hbsrecv_Csr;

         gInd.SflA_Empty = rrna = 0;
         returnnum = rrna;
         s#rrna = rrna;
         rrna = 1;

       Return;

       End-Proc;

       dcl-proc ViewClob;
         Dcl-PI *N int(10);
            inFile char(10) const;
            inField char(10) const;
            inGuid char(36) const;
         END-PI;

sas1     dcl-s ClobData varchar(2000000);
sas1     dcl-s ClobSQLData sqltype(CLOB: 2000000);
         dcl-s lines int(10);
         dcl-s lastbit int(10);
         dcl-s Clob_len int(10);
         dcl-s idx int(10);
         dcl-s mysql varchar(500);
         dcl-s guidkey char(10);
         dcl-s indent int(10);
         dcl-s strpos    int(10);
         dcl-s start  int(10);
         dcl-s end    int(10);
         dcl-s len    int(10);
         dcl-s mychar char(1);
         dcl-s nextchar char(1);
         dcl-s mydata char(125);
         dcl-s Data   char(125);
         dcl-s Blanks char(125) inz(*blanks);
         dcl-s formatting char(1);
         dcl-s inString ind inz(*off);

         dcl-c tic x'7D';

         formatting = 'J';

         select;
26001      when inFile = 'HBSREQ';
             guidkey = 'HRGUID';
26001      when inFile = 'HBSTRANS';
             guidkey = 'HTGUID';
26001      when inFile = 'HBRESP';
             guidkey = 'HSGUID';
        //    when inFile = 'HBSRECV';
        //      guidkey = 'HRACTVTID';
        //    when inFile = 'HBSSEND';
            //  guidkey = 'HSACTVTID';
           when inFile = 'HBSGUIDLOG';
             guidkey = 'HGACTVTID';
         endsl;

sas1     ClobSqlData_data = '';
sas1     ClobSqlData_len = 0;

sas1        mysql = 'select ' + %trim(inField) + ' ' +
sas1          'from ' + %trim(inFile) + ' ' +
sas1          'where ' + %trim(guidkey) + ' = ' + tic + %trim(inGuid) + tic;
         exec sql prepare s1 from :mysql;
         exec sql declare c1 cursor for s1;
         exec sql open c1;
sas1     exec sql fetch c1 into :ClobSqlData;
         exec sql close c1;

sas1     ClobData = %trim(ClobSqlData_data);
            Clob_len = %len(%trim(ClobData));

       HBSViewJSON(inFile
                  :guidkey
                  :inGuid
                  :''
                  :ClobData);

       return 0;

       end-proc;

       dcl-proc Prompt;
         Dcl-PI *N int(10);
            inField char(10) const;
            outValue char(40);
         END-PI;

         dcl-c tic x'7D';

         dow (1 = 1);

         gInd.SflC_Clear = *On;
         Write sflcc;
         gInd.Sflc_Clear = *off;
         gInd.Sflc_Empty = *off;
         rrnc = 0;

         if inField = 'FRSTAT';
           ListValue = 'E  Error';
           RetValue = 'E';
           rrnc += 1;
           write sflc;
           ListValue = 'N  Not Processed';
           RetValue = 'N';
           rrnc += 1;
           write sflc;
           ListValue = 'X  Manually Processed';
           RetValue = 'X';
           rrnc += 1;
           write sflc;
           ListValue = 'Y  Processed Normally';
           RetValue = 'Y';
           rrnc += 1;
           write sflc;
         endif;

         if inField = 'FSSTAT';
           ListValue = 'E  Error';
           RetValue = 'E';
           rrnc += 1;
           write sflc;
           ListValue = 'N  Not Processed';
           RetValue = 'N';
           rrnc += 1;
           write sflc;
           ListValue = 'S  Sent';
           RetValue = 'S';
           rrnc += 1;
           write sflc;
           ListValue = 'X  Manually Processed';
           RetValue = 'X';
           rrnc += 1;
           write sflc;
           ListValue = 'Y  Processed Normally';
           RetValue = 'Y';
           rrnc += 1;
           write sflc;
         endif;

         if inField = 'FSERVICE';
           ListValue = 'EditUserEntitlementsRequest - HBS214BR22';
           RetValue = 'EditUserEntitlementsRequest';
           rrnc += 1;
           write sflc;
           ListValue = 'GetAccountEnrollmentStatusRequest - HBSHS001';
           RetValue = 'GetAccountEnrollmentStatusRequest ';
           rrnc += 1;
           write sflc;
           ListValue = 'GetUserDetailsRequest - HBSCMUSR';
           RetValue = 'GetUserDetailsRequest';
           rrnc += 1;
           write sflc;
           ListValue = 'SubsystemHealthCheckRequest - HBSHS003';
           RetValue = 'SubsystemHealthCheckRequest';
           rrnc += 1;
           write sflc;
           ListValue = 'GetAchBatchDetailRequest - HBSHS002';
           RetValue = 'GetAchBatchDetailRequest';
           rrnc += 1;
           write sflc;
          rrnc= 1;
        endif;

         if inField = 'FSSERVICE';
           ListValue = 'HBS214BR22 - EditUserEntitlementsRequest';
           RetValue  = 'HBS214BR22';
           rrnc += 1;
           write sflc;
           ListValue = 'HBSHS001   - GetAccountEnrollmentStatusRequest';
           RetValue  = 'HBSHS001   ';
           rrnc += 1;
           write sflc;
           ListValue = 'HBSCMUSR   - GetUserDetailsRequest';
           RetValue  = 'HBSCMUSR   ';
           rrnc += 1;
           write sflc;
           ListValue = 'ALERT      - Alert Event';
           RetValue  = 'ALERT     ';
           rrnc += 1;
           write sflc;
           ListValue = 'LOGEVENT   - Log Event';
           RetValue  = 'LOGEVENT ';
           rrnc += 1;
           write sflc;
           ListValue = 'HBSCMEVT   - Maintenance Event';
           RetValue  = 'HBSCMEVT';
           rrnc += 1;
           write sflc;
          rrnc= 1;
        endif;

          write sflcf;
          exfmt sflcc;

          readc sflc;
          if option1 = '1';
            outValue = RetValue;
             leave;
          endif;

         if  gInd.Previous;
            leave;
         endif;
          enddo;

         if gInd.Previous;
           gInd.Previous = *off;
         endif;
       return 0;

       end-proc;

      // Build List
       Dcl-Proc Build_Out_List;

         gInd.SflD_Clear = *On;
         Write sflDc;
         gInd.SflD_Clear = *off;
         gInd.SflD_Empty = *off;
         crrnd = 0;
         rrnd = 0;

         SQLStatement = 'SELECT s.hsactvtid, s.hsparntid, '        +
           's.hsattmpt#, s.hsstat, s.hshstsrv,  '                  +
           'cast(s.hsrspnse as char(500)), '                       +
           'cast(s.hsrowmnt as char(26)),  '                       +
           'coalesce (hstsrvc, ' + tic + 'EXTERNAL' + tic +') , '  +
           'cast(s.hssndhdr as char(100)) '                         +
         'From hbssend s left join hbhsts on s.hshstsrv = hstsrvc ' +
         'where @W '                                               +
         'Order by '                                               +
         '  s.hsrowmnt desc '                                      +
         'For Read Only';

         SQLStatement = %scanrpl('@W':WhereStatement:SQLStatement);

         Exec SQL Prepare the_out_Csr from :SQLStatement;
         Exec SQL Declare hbssend_Csr Cursor for the_out_Csr;

         Exec SQL Open hbssend_Csr;

         DoU noMoreRows;
           Exec SQL
             Fetch Next From hbssend_Csr
             For :blockSize Rows
           Into :$dsOutREC;

           If sqlState = SQL_EndOfData;
              noMoreRows = *On;
              Leave;
           ElseIf sqlcode <> 0;
              If CheckSQLState(sqlstate) = 'C';
                 MsgHdlr(MessageType: GetSQLCode(sqlcode):MessageFile);
              EndIf;
           EndIf;

           BlockSize = SQL_FetchCount;
           NoMoreRows = SQL_LastRowIndicator = 100;
           For Index# = 1 To BlockSize;
25001          if rrnd >= 999;
                 gInd.TooMany = *on;
                 leave;
               endif;
               rrnd += 1;
               aguid   = $dsOutRec(index#).aguid;
               pguid   = $dsOutRec(index#).pguid;
               sservice = $dsOutRec(index#).sservice;
sasx           sndstat = $dsOutRec(index#).sndstat;
               attmps = $dsOutRec(index#).attmps;
               sndts   = $dsOutRec(index#).sndts;
               response = $dsOutRec(index#).response;
               if $dsOutRec(index#).type = 'EXTERNAL';
                 if $dsOUtRec(index#).sheader = 'INTERNAL';
                   otype = 'I';
                 else;
                  otype = ' ';
                 endif;
               else;
                 otype = 'H';
               endif;
               Write sfld;
           EndFor;
         EndDo;

         Exec Sql Close hbssend_Csr;

         gInd.SflD_Empty = rrnd = 0;
         returnnum = rrnd;
         s#rrnd = rrnd;
         rrnd = 1;

       Return;

       End-Proc;

       dcl-proc Init_in;

24001  dsHBSSBSCTL = GetDataArea('HBSSBSCTL':'*LIBL');

       hbssbsnam = d_SbsName;
       hbsrunlib = d_SbsLib;
       hbsdatlib = d_BankLib;

       // Default three days ago
25001  rdfr = %char(%date()-%days(3):*usa/);
       rtfr = %char(%time('00.00.00'):*HMS);

26001  WhereStatement = 'HTRCVTS >= ' + tic +
        %char(
        %timestamp(%char(%date(rdfr:*usa):*ISO) +
        '-' + %char(%time(rtfr:*HMS):*ISO) +
        '.000000')) + tic;
       WhereStatement = %trim(WhereStatement) +
26001    ' and HTREQHDR not like ' + tic +
26001    '%SubsystemControl%' + tic;

       end-proc;

       dcl-proc Show_In;

       Build_In_List();

       dow 1 = 1;

         if crrna > 1;
           rrna = crrna - 1;
         else;
           rrna = 1;
         endif;

         write sflaf;
         exfmt sflac;

         gInd.TooMany = *off;
         build = *off;
         if gInd.Exit or gInd.Previous;
            Exit = *on;
            return;
         endif;

         if gInd.Functions;

           clear wwparms;
           clear wwsbsjob;
           clear wwctlq;
           clear comtest;
           clear dispdata;
24002      clear dspversn;

           exfmt SF03;
           select;
             when wwparms = '1';
               HBSParms();
             when wwsbsjob = '1';
               clear CmdString;
               CmdString = 'WRKSBSJOB SBS(' +
                        %trim(HBSSBSNAM) + ')';
               exec sql
                 call qsys2.qcmdexc(:CmdString);
             when wwctlq = '1';
               HBSWorkCtlQ();
             when comtest = '1';
               HBSComTest();
             when dispdata = '1';
               HBSDispDataArea();
24002        when dspversn = '1';
24002          HBSSubfileService('VERSION'
24002                           :'V'
24002                           :Input1
24002                           :Input2
24002                           :Input3
24002                           :Value1
24002                           :Value2
24002                           :Value3
               );
           endsl;

         endif;

         if gInd.Swap;
           SwapDirection = *on;
           return;
         endif;

         if gInd.Refresh;
           build = *on;
         endif;

         if gInd.Parameters;
           HBSParms();
         endif;

         if gInd.WrkSbs;
           clear CmdString;
           CmdString = 'WRKSBSJOB SBS(' +
                        %trim(HBSSBSNAM) + ')';
           exec sql
             call qsys2.qcmdexc(:CmdString);
         endif;

         if gInd.Filter;

           done = *off;

           dow not(done);
           exfmt SF01;

           if gInd.Prompt;
             select;
               when Fld = 'FRSTAT';
                 Prompt('FRSTAT': rtnvalue);
                 frstat = rtnvalue;
               when Fld = 'FSSTAT';
                 Prompt('FSSTAT': rtnvalue);
                 fsstat = rtnvalue;
               when Fld = 'FSERVICE';
24002            HBSSubfileService('VERSION'
24002                             :'S'
24002                             :Input1
24002                             :Input2
24002                             :Input3
24002                             :Value1
24002                             :Value2
24002                             :Value3
24002                             );
24002              fservice = Value1;
             endsl;
             iter;
           endif;
           if gInd.Previous;
             done = *on;
             iter;
           endif;

           error = *off;
           gInd.RecFromDateInvalid = *off;
           gInd.RecFromTimeInvalid = *off;
           gInd.RecToDateInvalid = *off;
           gInd.RecToTimeInvalid = *off;

          if rdfr <> *blanks;
            test(de) *usa rdfr;
            if %error;
              gInd.RecFromDateInvalid = *on;
              error = *on;
            endif;
          endif;

          if rdfr <> *blanks and not(gInd.RecFromDateInvalid);
            if rtfr = *blanks or rtfr = '0       ';
              rtfr = '00:00:00';
            endif;
          endif;

          if rtfr <> *blanks;
            test(et) *hms rtfr;
            if %error;
              gInd.RecFromTimeInvalid = *on;
              error = *on;
            endif;
          endif;

          if rdto <> *blanks;
            test(de) *usa rdto;
            if %error;
              gInd.RecToDateInvalid = *on;
              error = *on;
            endif;
          endif;

          if rdto <> *blanks and not(gInd.RecToDateInvalid);
            if rtto = *blanks or rtto = '0       ';
              rtto = '00:00:00';
            endif;
          endif;

          if rtto <> *blanks;
            test(et) *hms rtto;
            if %error;
              gInd.RecToTimeInvalid = *on;
              error = *on;
            endif;
          endif;

           if not(error);
           reset WhereStatement;

          if faguid <> *blanks;
26001       WhereStatement = 'HTGUID = ' + tic +
            faguid + tic;
          endif;

          if fraguid <> *blanks;
26001       if WhereStatement = *blanks;
26001         WhereStatement = 'HTRQAGUID = ' + tic +
                fraguid + tic;
26001       else;
26001         WhereStatement += ' AND HTRQAGUID = ' + tic +
                fraguid + tic;
26001       endif;
          endif;

          if frpguid <> *blanks;
26001       if WhereStatement = *blanks;
26001         WhereStatement = 'HTRQPGUID = ' + tic +
                frpguid + tic;
26001       else;
26001         WhereStatement += ' AND HTRQPGUID = ' + tic +
                frpguid + tic;
26001       endif;
          endif;

          if frstat <> *blanks;
26001       if WhereStatement = *blanks;
26001         WhereStatement = 'HTRCVSTS = ' + tic +
                frstat + tic;
26001       else;
26001         WhereStatement += ' AND HTRCVSTS = ' + tic +
                frstat + tic;
26001       endif;
          endif;
          if fsstat <> *blanks;
            if WhereStatement = *blanks;
26001         WhereStatement = 'HTSNDSTS = ' + tic +
              fsstat + tic;
            else;
26001         WhereStatement += ' AND HTSNDSTS = ' + tic +
              fsstat + tic;
            endif;
          endif;
          if fservice <> *blanks;
            if WhereStatement = *blanks;
26001         WhereStatement = 'HTSNAME like '
               + tic + '%' +
               %trim(fservice) + '%' + tic;
            else;
26001         WhereStatement += ' AND HTSNAME like '
               + tic + '%' +
               %trim(fservice) + '%' + tic;
            endif;
          endif;
          if rdfr <> *blanks;
            if WhereStatement = *blanks;
26001         WhereStatement = 'HTRCVTS >= ' + tic +
                %char(
                %timestamp(%char(%date(rdfr:*usa):*ISO) +
                '-' + %char(%time(rtfr:*HMS):*ISO) +
                '.000000')) + tic;
            else;
26001         WhereStatement += ' AND HTRCVTS >= ' + tic +
                %char(
                %timestamp(%char(%date(rdfr:*usa):*ISO) +
                '-' + %char(%time(rtfr:*HMS):*ISO) +
                '.000000')) + tic;
            endif;
          endif;

          if rdto <> *blanks;
            if WhereStatement = *blanks;
26001         WhereStatement = 'HTRCVTS <= ' + tic +
                %char(
                %timestamp(%char(%date(rdto:*usa):*ISO) +
                '-' + %char(%time(rtto:*HMS):*ISO) +
                '.000000')) + tic;
            else;
26001         WhereStatement += ' AND HTRCVTS <= ' + tic +
                %char(
                %timestamp(%char(%date(rdto:*usa):*ISO) +
                '-' + %char(%time(rtto:*HMS):*ISO) +
                '.000000')) + tic;
            endif;
          endif;
26001  if WhereStatement = *blanks;
26001    WhereStatement = 'HTREQHDR not like ' + tic +
26001      '%SubsystemControl%' + tic;
26001  else;
26001    WhereStatement += ' AND HTREQHDR not like ' + tic +
26001      '%SubsystemControl%' + tic;
26001  endif;

          done = *on;
          endif;

          enddo;

          build = *on;

         endif;
         // Function keys
         select;
         other;
             Changed = *off;
             if gInd.Sfla_Empty = *off;
               readc sfla;
               test1 = crrna;
               dow not(%eof);
                 // Subfile Options
                 select;
26001            when option2 = 'RD';
                   ViewCLOB('HBSREQ': 'HRBODY': AGuid);
                 when %trim(option2) = 'V';
26001              ShowDetail(AGuid);
                 when option2 = 'RH';
                   ViewCLOB('HBSTRANS': 'HTREQHDR': AGuid);
                 when option2 = 'SD';
                   ViewClob('HBRESP': 'HSBODY': AGuid);
                 when option2 = 'SH';
                   ViewClob('HBSTRANS': 'HTRESHDR': AGuid);
                //  when option2 = 'SR';
                //    ViewClob('HBSSEND': 'HSRSPNSE': AGuid);
                 when %trim(option2) = 'L';
                   ViewClob('HBSGUIDLOG': 'HGJSONLOG': AGuid);
                //  when %trim(option2) = 'V';
                //    ViewJSON(AGuid);
                 when %trim(option2) = '2';
                   outpguid = PGuid;
                   outaguid = AGuid;
                   outservice = SService;
                   oldstatus = SndStat;
                   exfmt SF04;
                 when %trim(option2) = 'DB';
                   DebugService(AGuid: HostPgm);
                 when %trim(option2) = 'R';
                   respguid = PGuid;
                   resaguid = AGuid;
                   resservice = Service;
                   resstatus = rcvStat;
                   exfmt SF05;
                   if gInd.ResetReq;
26001                exec sql
26001                  update hbstrans
26001                    set htrcvsts = 'N', htsndsts = 'N'
26001                    where htguid = :AGuid;
26001                exec sql
26001                  delete from hbresp
26001                    where hsguid = :AGuid;
                   endif;
                    build = *on;
                 endsl;

                 clear option2;
                 update sfla;
                   readc sfla;
               enddo;
             endif;
         endsl;

           // Rebuild
           if gInd.Exit = *off;
             if build = *on;
               Build_In_List();
             endif;
           endif;

       enddo;

       end-proc;

       dcl-proc Show_Out;

25001  sdfr = %char(%date()-%days(3):*usa/);
       stfr = %char(%time('00.00.00'):*HMS);

       WhereStatement = 's.hsrowmnt >= ' + tic +
        %char(
        %timestamp(%char(%date(rdfr:*usa):*ISO) +
        '-' + %char(%time(rtfr:*HMS):*ISO) +
        '.000000')) + tic;

       Build_Out_List();

       dow 1 = 1;

         if crrnd > 1;
           rrnd = crrnd - 1;
         else;
           rrnd = 1;
         endif;

         write sfldf;
         exfmt sfldc;

         gInd.TooMany = *off;
         build = *off;
         if gInd.Exit or gInd.Previous;
            Exit = *on;
            return;
         endif;

        if gInd.Functions;

           clear wwparms;
           clear wwsbsjob;
           clear wwctlq;
24002      clear comtest;
24002      clear dispdata;
24002      clear dspversn;
           exfmt SF03;
           select;
             when wwparms = '1';
               HBSParms();
             when wwsbsjob = '1';
               clear CmdString;
               CmdString = 'WRKSBSJOB SBS(' +
                        %trim(HBSSBSNAM) + ')';
               exec sql
                 call qsys2.qcmdexc(:CmdString);
             when wwctlq = '1';
               HBSWorkCtlQ();
24002        when comtest = '1';
24002          HBSComTest();
24002        when dispdata = '1';
24002          HBSDispDataArea();
24002        when dspversn = '1';
24002          HBSSubfileService('VERSION'
24002                           :'V'
24002                           :Input1
24002                           :Input2
24002                           :Input3
24002                           :Value1
24002                           :Value2
24002                           :Value3
               );
           endsl;

         endif;
         if gInd.Swap;
           SwapDirection = *on;
           return;
         endif;

         if gInd.Refresh;
           build = *on;
         endif;

         if gInd.Filter;

           done = *off;

           dow not(done);
           exfmt SF02;

           if gInd.Prompt;
             select;
               when Fld = 'FSSTAT';
                 Prompt('FSSTAT': rtnvalue);
                 fsstat = rtnvalue;
               when Fld = 'FSSERVICE';
24002            HBSSubfileService('OUTPROGRAM'
24002                           :'S'
24002                           :Input1
24002                           :Input2
24002                           :Input3
24002                           :Value1
24002                           :Value2
24002                           :Value3
24002                           );
24002            fsservice = Value1;
             endsl;
             iter;
           endif;
           if gInd.Previous;
             done = *on;
             iter;
           endif;

           error = *off;
           gInd.RecFromDateInvalid = *off;
           gInd.RecFromTimeInvalid = *off;
           gInd.RecToDateInvalid = *off;
           gInd.RecToTimeInvalid = *off;

          if sdfr <> *blanks;
            test(de) *usa sdfr;
            if %error;
              gInd.RecFromDateInvalid = *on;
              error = *on;
            endif;
          endif;

          if sdfr <> *blanks and not(gInd.RecFromDateInvalid);
            if stfr = *blanks or stfr = '0       ';
              stfr = '00:00:00';
            endif;
          endif;

          if stfr <> *blanks;
            test(et) *hms stfr;
            if %error;
              gInd.RecFromTimeInvalid = *on;
              error = *on;
            endif;
          endif;

          if sdto <> *blanks;
            test(de) *usa sdto;
            if %error;
              gInd.RecToDateInvalid = *on;
              error = *on;
            endif;
          endif;

          if sdto <> *blanks and not(gInd.RecToDateInvalid);
            if stto = *blanks or stto = '0       ';
              stto = '00:00:00';
            endif;
          endif;

          if stto <> *blanks;
            test(et) *hms stto;
            if %error;
              gInd.RecToTimeInvalid = *on;
              error = *on;
            endif;
          endif;

           if not(error);
           reset WhereStatement;

          if fpguid <> *blanks;
            WhereStatement = 's.HSPARNTID = ' + tic +
            fpguid + tic;
          endif;

          if faguid <> *blanks;
              WhereStatement = 's.HSACTVTID = ' + tic +
              faguid + tic;
          endif;

          if fsstat <> *blanks;
            if WhereStatement = *blanks;
              WhereStatement = 's.hsstat = ' + tic +
              fsstat + tic;
            else;
              WhereStatement += ' AND s.hsstat = ' + tic +
              fsstat + tic;
            endif;
          endif;
          if fsservice <> *blanks;
            if WhereStatement = *blanks;
              WhereStatement = 's.HSHSTSRV = ' + tic +
               %trim(fsservice) + tic;
            else;
              WhereStatement += ' AND s.HSHSTSRV = ' + tic +
               %trim(fsservice) + tic;
            endif;
          endif;
          if sdfr <> *blanks;
            if WhereStatement = *blanks;
              WhereStatement = 's.hsrowmnt >= ' + tic +
                %char(
                %timestamp(%char(%date(sdfr:*usa):*ISO) +
                '-' + %char(%time(stfr:*HMS):*ISO) +
                '.000000')) + tic;
            else;
              WhereStatement += ' AND s.hsrowmnt >= ' + tic +
                %char(
                %timestamp(%char(%date(sdfr:*usa):*ISO) +
                '-' + %char(%time(stfr:*HMS):*ISO) +
                '.000000')) + tic;
            endif;
          endif;

          if sdto <> *blanks;
            if WhereStatement = *blanks;
              WhereStatement = 's.hsrowmnt <= ' + tic +
                %char(
                %timestamp(%char(%date(sdto:*usa):*ISO) +
                '-' + %char(%time(stto:*HMS):*ISO) +
                '.000000')) + tic;
            else;
              WhereStatement += ' AND s.hsrowmnt <= ' + tic +
                %char(
                %timestamp(%char(%date(sdto:*usa):*ISO) +
                '-' + %char(%time(stto:*HMS):*ISO) +
                '.000000')) + tic;
            endif;
          endif;

          done = *on;
          endif;

          enddo;

          build = *on;

         endif;
         // Function keys
         select;
         other;
             Changed = *off;
             if gInd.Sfld_Empty = *off;
               readc sfld;
               test1 = crrnd;
               dow not(%eof);
                 // Subfile Options
                 select;
                 when option2 = 'SD';
                   ViewClob('HBSSEND': 'HSSNDDTA': AGuid);
                 when option2 = 'SH';
                   ViewClob('HBSSEND': 'HSSNDHDR': AGuid);
                 when option2 = 'SR';
                   ViewClob('HBSSEND': 'HSRSPNSE': AGuid);
                 when %trim(option2) = 'L';
                   ViewClob('HBSGUIDLOG': 'HGJSONLOG': AGuid);
                 when %trim(option2) = '2';
                   outpguid = PGuid;
                   outaguid = AGuid;
                   outservice = SService;
                   oldstatus = SndStat;
                   exfmt SF04;
                   exec sql
                     update hbssend
                       set hsstat = :newstatus
                       where hsactvtid = :AGuid;
                    build = *on;
                 endsl;

                 clear option2;
                 update sfld;
                   readc sfld;
               enddo;
             endif;
         endsl;

           // Rebuild
           if gInd.Exit = *off;
             if build = *on;
               Build_Out_List();
             endif;
           endif;

       enddo;

       end-proc;


      //---------------------------------------------------------
      // ParseJSON - Parse JSON string
      //---------------------------------------------------------
       dcl-proc ParseJSON;
         dcl-pi *n;
           pJSON varchar(5000);
         END-PI;

         data-into RcvResp %DATA(pJSON
                         : 'doc=string case=convert countprefix= num_ -
                         allowextra=yes allowmissing=yes')
                                %PARSER('YAJLINTO');

         return;

       end-proc;

       dcl-proc ViewJSON;
         dcl-pi *n;
           pGUID char(36);
         end-pi;

       open hbslogx1;

       chain (pGUID) hbslogx1;

       HBSViewJSON('HBSLOGF'
                  :'LOINFO'
                  :LOGUID
                  :'REF2'
                  :LOINFO);

       close hbslogx1;

       end-proc;


      //---------------------------------------------------------
      // ShowDetail - Display HBSTRANS detail screen (SF06)
      //---------------------------------------------------------
26001  dcl-proc ShowDetail;
26001    dcl-pi *n;
26001      pGuid char(36) const;
26001    end-pi;
26001
26001    exec sql
26001      select HTRQAGUID, HTRQPGUID, HTTYPE,
26001             HTRCVSTS, HTSNDSTS, HTATTEMPTS,
26001             cast(HTRCVTS as char(26)),
26001             cast(HTSNDTS as char(26)),
26001             HTSNAME, HTPNAME
26001        into :dsSF06.aguid,  :dsSF06.pguid,  :dsSF06.type,
26001             :dsSF06.rcvsts, :dsSF06.sndsts, :dsSF06.attmps,
26001             :dsSF06.rcvts,  :dsSF06.sndts,
26001             :dsSF06.sname,  :dsSF06.pname
26001        from hbstrans
26001        where HTGUID = :pGuid;
26001
26001    d6aguid  = dsSF06.aguid;
26001    d6pguid  = dsSF06.pguid;
26001    d6type   = dsSF06.type;
26001    d6rcvsts = dsSF06.rcvsts;
26001    d6sndsts = dsSF06.sndsts;
26001    d6attmps = dsSF06.attmps;
26001    d6rcvts  = dsSF06.rcvts;
26001    d6sndts  = dsSF06.sndts;
26001    d6sname  = %trim(dsSF06.sname);
26001    d6pname  = dsSF06.pname;
26001    d6opt    = *blanks;
26001
26001    dow gInd.Previous = *off;
26001      exfmt SF06;
26001      if gInd.Previous;
26001        leave;
26001      endif;
26001      select;
26001        when %trim(d6opt) = 'RH';
26001          ViewCLOB('HBSREQ'  : 'HRBODY'  : pGuid);
26001        when %trim(d6opt) = 'SH';
26001          ViewCLOB('HBRESP'  : 'HSBODY'  : pGuid);
26001      endsl;
26001      d6opt = *blanks;
26001    enddo;
26001
26001  end-proc;

24001  dcl-proc GetDataArea;
24001    dcl-pi *n char(1024);
24001      p_DataArea char(10) const;
24001      p_Library char(10) const;
24001    end-pi;
24001
24001  dcl-s DataString char(1024);
24001
24001  clear DataString;
24001
24001    exec sql
24001     SELECT DATA_AREA_VALUE into :DataString
24001       FROM TABLE(QSYS2.DATA_AREA_INFO(
24001            DATA_AREA_NAME => :p_DataArea,
24001            DATA_AREA_LIBRARY => :p_Library));
24001
24001   return DataString;
24001
24001  end-proc;
