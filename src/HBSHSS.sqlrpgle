      // Create command
      *> CRTSQLRPGI OBJ(&O/&ON) SRCFILE(&L/QRPGLESRC) -
      *> OBJTYPE(*PGM) OUTPUT(*NONE) RPGPPOPT(*LVL2) DBGVIEW(*SOURCE)

       Ctl-Opt Option(*SrcStmt: *NODebugIO);
       Ctl-Opt BndDir('HBSBIND');
       Ctl-Opt ActGrp(*Caller);
      // ---------------------------------------------------------//
      //   Copyright 1988-2024 by:  Jack Henry & Associates, Inc. //
      //                         Monett, Missouri  65708          //
      // ---------------------------------------------------------//

24000 // 10/07/24 #1180779 S Smith - Dashboard V3

       //dcl-f hbslogx1 keyed usage(*input) usropn;
       Dcl-F hbshssfm WorkStn IndDS(gInd) sfile(sfla : rrna);

       // EntryParm
       Dcl-PI *N;
         pService char(10) const;
         pFunction char(1) const;
         pInput1 char(50) const;
         pInput2 char(50) const;
         pInput3 char(50) const;
         oValue1 char(50);
         oValue2 char(50);
         oValue3 char(50);

       END-PI;

       // Data Structures -----------------------------------------------------
       Dcl-DS gInd Qualified;
          Exit         Ind Pos(03) Inz(*Off);
          Prompt       Ind Pos(04) Inz(*off);
          Refresh      Ind Pos(05) Inz(*off);
          Format       Ind Pos(08) Inz(*off);
          Filter       Ind Pos(09) Inz(*off);
          Swap         Ind Pos(11) Inz(*Off);
          Previous     Ind Pos(12) Inz(*Off);
          TooMany      Ind Pos(30) Inz(*off);
          ViewOnly     Ind Pos(40) Inz(*off);
          SflA_Empty    Ind Pos(64) Inz(*Off);
          SflA_Clear    Ind Pos(65) Inz(*Off);
          SflA_End      Ind Pos(66) Inz(*Off);

       End-DS;

       dcl-ds dsJSONPackage qualified template;
         PGUID char(36) inz('');
         AGUID char(36) inz('');
         clob varchar(2000000) inz('');
       end-ds;

       dcl-s @RequestPtr  pointer;
       dcl-s @ResponsePtr pointer;
       dcl-ds dsRequest likeds(dsJSONPackage); // based(@RequestPtr);
       dcl-ds dsResponse likeds(dsJSONPackage) based(@ResponsePtr);

       dcl-ds HBSHS013_Req qualified;
         SortBy char(10) inz('');
         dcl-ds EndUser;
           InternalId varchar(25) inz('');
           InternalSecondaryId varchar(25) inz('');
           UserType int(10) inz(0);
         end-ds;

         dcl-ds ActivityTracking;
           ActivityId varchar(36) inz('');
           ParentActivityId varchar(36) inz('');
         end-ds;
         ApplicationNameType packed(2) inz(0);
         ClientIpAddress varchar(15) inz('');
         InstitutionId varchar(13) inz('');
       end-ds;

       dcl-ds HBSHS013_Res qualified;
         Success ind inz('0');
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
       //  dcl-ds BaseRequest likeds(dsReqJSON);
       end-ds;

       dcl-ds HBSHS017_Req qualified;
         LogActivityID char(36) inz('');
         dcl-ds EndUser;
           InternalId varchar(25) inz('');
           InternalSecondaryId varchar(25) inz('');
           UserType int(10) inz(0);
         end-ds;

         dcl-ds ActivityTracking;
           ActivityId varchar(36) inz('');
           ParentActivityId varchar(36) inz('');
         end-ds;
         ApplicationNameType packed(2) inz(0);
         ClientIpAddress varchar(15) inz('');
         InstitutionId varchar(13) inz('');
       end-ds;

       dcl-ds HBSHS017_Res qualified;
         Success ind inz('0');
         num_ResponseDetailCollection int(10) inz(0);
         dcl-ds ResponseDetailCollection dim(20);
           ResponseCode int(10) inz(0);
           ResponseMessage varchar(200) inz('');
         end-ds;
         RecordsAffected int(10) inz(0);
         num_ErrLog int(10) inz(0);
         dcl-ds ErrLog dim(500);
           Category char(10) inz('');
           Type char(10) inz('');
           Error char(10) inz('');
           Program char(10) inz('');
           JobName char(10) inz('');
           JobNumber char(10) inz('');
           TimeStamp char(26) inz('');
           Description varchar(2000);
         end-ds;
       //  dcl-ds BaseRequest likeds(dsReqJSON);
       end-ds;

       dcl-ds HBSHS018_Req qualified;
         SelectType char(1) inz('');
         dcl-ds EndUser;
           InternalId varchar(25) inz('');
           InternalSecondaryId varchar(25) inz('');
           UserType int(10) inz(0);
         end-ds;

         dcl-ds ActivityTracking;
           ActivityId varchar(36) inz('');
           ParentActivityId varchar(36) inz('');
         end-ds;
         ApplicationNameType packed(2) inz(0);
         ClientIpAddress varchar(15) inz('');
         InstitutionId varchar(13) inz('');
       end-ds;

       dcl-ds HBSHS018_Res qualified;
         Success ind inz('0');
         num_ResponseDetailCollection int(10) inz(0);
         dcl-ds ResponseDetailCollection dim(20);
           ResponseCode int(10) inz(0);
           ResponseMessage varchar(200) inz('');
         end-ds;
         RecordsAffected int(10) inz(0);
         num_OutProgramList int(10) inz(0);
         dcl-ds OutProgramList dim(500);
           Type char(1) inz('');
           HostProgram char(10) inz('');
           HostService char(40) inz('');
         end-ds;
       //  dcl-ds BaseRequest likeds(dsReqJSON);
       end-ds;

       dcl-pr MyHostProgram  Extpgm(pHostProgram);
         pInputPtr pointer;
         pOutputPtr pointer;
         pService char(40);
         pVersion char(40);
         pRtnOpts char(40);
       end-pr;

       dcl-ds myData likeds(HBSHS013_Res) inz;

       dcl-ds myReqData likeds(HBSHS013_Req) inz;

       // Copy Books ----------------------------------------------------------

       /include qcpysrc,hbstools
       /include qcpysrc,hbspsds
       /include qcpysrc,jhdateucpy
       /copy qcpysrc,sqlstruct

      // Misc. Field Declarations

sas1     dcl-s ClobData varchar(2000000);
sas1     dcl-s ClobSQLData sqltype(CLOB: 2000000);
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

       dcl-s guid1 char(36);
       dcl-s guid2 char(36);
       dcl-s RequestString varchar(2000);
       dcl-s pHostProgram char(10);
       dcl-s myService char(40);
       dcl-s myVersion char(40);
       dcl-s myRtnOpts char(40);
       dcl-s idx1 int(10);

       Dcl-S Index# Int(10);
       Dcl-S noMoreRows Ind;
       //
       Exec SQL
         Set Option
            commit = *none,
            CloSqlCsr = *endmod,
            Datfmt = *iso;


       guid1 = hbstools_CrtGuid();
       guid2 = hbstools_CrtGuid();

       dsRequest.AGUID = guid1;
       dsRequest.PGUID = guid2;

       select;
         when pFunction = 'V';
           gInd.ViewOnly = *on;
         when pFunction = 'S';
           gInd.ViewOnly = *off;
       endsl;

       select;
         when pService = 'VERSION';
           pHostProgram = 'HBSHS013';
           sfltitle = '                       Host Se' +
                      'rvices                        ';
           sflheader = 'Service Name                             ' +
                       'Program    ' +
                       'Version';
           HBSHS013_Req.SortBy = %trim(pInput1);
           HBSHS013_Req.ActivityTracking.ActivityId = guid1;
           HBSHS013_Req.ActivityTracking.ParentActivityId = guid1;
           CrtHBSHS013Json(dsRequest.clob);
         when pService = 'HBSLOGF';
           pHostProgram = 'HBSHS017';
           sfltitle = '                        HBS LO' +
                      'GF Entries                    ';
           sflheader = 'Category   Type       Error      Program ' +
                       '   Job        Description';
           HBSHS017_Req.LogActivityID = %trim(pInput1);
           HBSHS017_Req.ActivityTracking.ActivityId = guid1;
           HBSHS017_Req.ActivityTracking.ParentActivityId = guid1;
           CrtHBSHS017Json(dsRequest.clob);
         when pService = 'OUTPROGRAM';
           pHostProgram = 'HBSHS018';
           sfltitle = '                     Outbound ' +
                      'Services                      ';
           sflheader = 'Type Host Program  Host Service          ' +
                       '                         ';
           HBSHS018_Req.SelectType = %trim(pInput1);
           HBSHS018_Req.ActivityTracking.ActivityId = guid1;
           HBSHS018_Req.ActivityTracking.ParentActivityId = guid1;
           CrtHBSHS018Json(dsRequest.clob);
       endsl;


       @ResponsePtr = *null;
       @RequestPtr = %addr(dsRequest);

       MyHostProgram(@RequestPtr
                    :@ResponsePtr
                    :myService
                    :myVersion
                    :myRtnOpts);

       select;
         when pService = 'VERSION';
           ParseHBSHS013Json(dsResponse.clob);
         when pService = 'HBSLOGF';
           ParseHBSHS017Json(dsResponse.clob);
         when pService = 'OUTPROGRAM';
           ParseHBSHS018Json(dsResponse.clob);
       endsl;

       // default to inbound;
       InitList();
       dow 1 = 1;
             ShowList();
         if Exit;
           leave;
         endif;


       enddo;

       *inlr = *on;

      //---------------------------------------------------------
      // Create HBSHS013 Json
      //---------------------------------------------------------
       dcl-proc CrtHBSHS013Json;
         dcl-pi *n ind;
           pJson varchar(2000000);
         end-pi;

       dcl-s DataGenOptions varchar(200);

       DataGenOptions = 'doc=string output=clear countprefix=num_';

         %len(pJson) = 0;
         pJson = '';

         DATA-GEN HBSHS013_Req
           %DATA(pJson: DataGenOptions)
           %GEN('YAJLDTAGEN');

         return *on;

       end-proc;
      //---------------------------------------------------------
      // Create HBSHS017 Json
      //---------------------------------------------------------
       dcl-proc CrtHBSHS017Json;
         dcl-pi *n ind;
           pJson varchar(2000000);
         end-pi;

       dcl-s DataGenOptions varchar(200);

       DataGenOptions = 'doc=string output=clear countprefix=num_';

         %len(pJson) = 0;
         pJson = '';

         DATA-GEN HBSHS017_Req
           %DATA(pJson: DataGenOptions)
           %GEN('YAJLDTAGEN');

         return *on;

       end-proc;
      //---------------------------------------------------------
      // Create HBSHS018 Json
      //---------------------------------------------------------
       dcl-proc CrtHBSHS018Json;
         dcl-pi *n ind;
           pJson varchar(2000000);
         end-pi;

       dcl-s DataGenOptions varchar(200);

       DataGenOptions = 'doc=string output=clear countprefix=num_';

         %len(pJson) = 0;
         pJson = '';

         DATA-GEN HBSHS018_Req
           %DATA(pJson: DataGenOptions)
           %GEN('YAJLDTAGEN');

         return *on;

       end-proc;

      //---------------------------------------------------------
      // Parse HBSHS013 JSON
      //---------------------------------------------------------
       dcl-proc ParseHBSHS013Json;
         dcl-pi *n;
           pJSON varchar(2000000);
         END-PI;

       dcl-s DataIntoOptions varchar(200);
       dcl-s YajlIntoOptions varchar(200);

       DataIntoOptions = 'doc=string case=convert countprefix= num_  -
         allowextra=yes allowmissing=yes';

       YajlIntoOptions = '{ "skip_null": true}';

         data-into HBSHS013_Res
           %DATA(pJSON: DataIntoOptions)
           %PARSER('YAJLINTO': YajlINtoOptions);

         return;

       end-proc;
      //---------------------------------------------------------
      // Parse HBSHS017 JSON
      //---------------------------------------------------------
       dcl-proc ParseHBSHS017Json;
         dcl-pi *n;
           pJSON varchar(2000000);
         END-PI;

       dcl-s DataIntoOptions varchar(200);
       dcl-s YajlIntoOptions varchar(200);

       DataIntoOptions = 'doc=string case=convert countprefix= num_  -
         allowextra=yes allowmissing=yes';

       YajlIntoOptions = '{ "skip_null": true}';

         data-into HBSHS017_Res
           %DATA(pJSON: DataIntoOptions)
           %PARSER('YAJLINTO': YajlINtoOptions);

         return;

       end-proc;
      //---------------------------------------------------------
      // Parse HBSHS018 JSON
      //---------------------------------------------------------
       dcl-proc ParseHBSHS018Json;
         dcl-pi *n;
           pJSON varchar(2000000);
         END-PI;

       dcl-s DataIntoOptions varchar(200);
       dcl-s YajlIntoOptions varchar(200);

       DataIntoOptions = 'doc=string case=convert countprefix= num_  -
         allowextra=yes allowmissing=yes';

       YajlIntoOptions = '{ "skip_null": true}';

         data-into HBSHS018_Res
           %DATA(pJSON: DataIntoOptions)
           %PARSER('YAJLINTO': YajlINtoOptions);

         return;

       end-proc;
       //----------------------------------------------------------------------
      // Build List
       Dcl-Proc BuildList;
         dcl-pi *n;
           pService char(10) const;
         end-pi;

       gInd.Sfla_Clear = *On;
       Write sflac;
       gInd.Sfla_Clear = *off;
       gInd.Sfla_Empty = *off;
       crrna = 0;
       rrna = 0;
       //
       //
       select;
         when pService = 'VERSION';
           for idx1 = 1 to HBSHS013_Res.num_ServiceList;
             sfltext = HBSHS013_Res.ServiceList(idx1).ServiceName + ' ' +
                       HBSHS013_Res.ServiceList(idx1).HostProgram + ' ' +
                       %trim(HBSHS013_Res.ServiceList(idx1).Version);
             sflvalue1 = HBSHS013_Res.ServiceList(idx1).ServiceName;
             sflvalue2 = *blanks;
             sflvalue3 = *blanks;
             rrna += 1;
             write sfla;
           endfor;
         when pService = 'HBSLOGF';
           for idx1 = 1 to HBSHS017_Res.num_ErrLog;
             sfltext = HBSHS017_Res.ErrLog(idx1).Category + ' ' +
                       HBSHS017_Res.ErrLog(idx1).Type + ' ' +
                       HBSHS017_Res.ErrLog(idx1).Error + ' ' +
                       HBSHS017_Res.ErrLog(idx1).Program + ' ' +
                       HBSHS017_Res.ErrLog(idx1).JobName + ' ' +
                       %trim(HBSHS017_Res.ErrLog(idx1).Description);
             sflvalue1 = *blanks;
             sflvalue2 = *blanks;
             sflvalue3 = *blanks;
             rrna += 1;
             write sfla;
           endfor;
         when pService = 'OUTPROGRAM';
           for idx1 = 1 to HBSHS018_Res.num_OutProgramList;
             sfltext = ' ' + HBSHS018_Res.OutProgramList(idx1).Type + '   ' +
                       HBSHS018_Res.OutProgramList(idx1).HostProgram + '    ' +
                       HBSHS018_Res.OutProgramList(idx1).HostService;
             sflvalue1 = HBSHS018_Res.OutProgramList(idx1).HostProgram;
             sflvalue2 = *blanks;
             sflvalue3 = *blanks;
             rrna += 1;
             write sfla;
           endfor;
       endsl;

         gInd.SflA_Empty = rrna = 0;
         returnnum = rrna;
         s#rrna = rrna;
         rrna = 1;
       
       Return;

       End-Proc;


       dcl-proc InitList;

       //WhereStatement = '1 = 1';

       end-proc;

       dcl-proc ShowList;

       BuildList(pService);

       dow 1 = 1;

         if crrna > 1;
           rrna = crrna - 1;
         else;
           rrna = 1;
         endif;

         write sflaf;
         exfmt sflac;

       // Reset Errors and Messages
       //  reset Error;
         gInd.TooMany = *off;
         build = *off;
         if gInd.Exit or gInd.Previous;
       //     leave;
            Exit = *on;
            return;
         endif;


         if gInd.Refresh;
           build = *on;
         endif;

         // Function keys
         select;
         other;
             Changed = *off;
       
               readc sfla;
               test1 = crrna;
               dow not(%eof);
                 select;
                   when %trim(option) = '1';
                     oValue1 = %trim(sflvalue1);
                     Exit = *on;
                     return;
       
                 endsl;
                 clear option;
                 update sfla;
                   readc sfla;
               enddo;
       //      endif;
         endsl;

           // Function Keys

           // Rebuild
           if gInd.Exit = *off;
             if build = *on;
               BuildList(pService);
             endif;
           endif;

       enddo;

       end-proc;
