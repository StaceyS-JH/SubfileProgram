       ctl-opt option(*srcstmt : *nodebugio);
       ctl-opt bnddir('JHIGNM':'HBSBIND');
       //ctl-opt main(HBSCMEVT);
sasn   ctl-opt bnddir('NOXDB');

25001 //  02/21/25 #1182418 MCollins - Add "Key" key/value pair to msg
24001 //  06/5/24  #1179375   V Everett - expand HBSSBSCTL
23002 //  09/15/23 #1177741 S Smith - changes for CL calling program
23001 //  09/05/23 #1177516 S Smith - psds changes
      //  12/27/22 #xxxxxxx MCollins - New Service
      //
      //  NetTeller HBS Cash Mgmt Event Service
      // ------------------------------------------------------- //
      // THIS PROGRAM IS PART OF SILVERLAKE SYSTEM (R)           //
      // Copyright 1988-2019 by:                                 //
      //                     JACK HENRY & ASSOCIATES, INC.       //
      //                     MONETT, MISSOURI  65708             //
      // ------------------------------------------------------- //

       dcl-f hbmant_t keyed usage(*input) usropn;

       /include qcpysrc,hbstools
       /include qcpysrc,hbspsds
sasn   /include qcpysrc,noxdb

       /define HbsSbsCtl
       /define JsonParserOptions
       /include qcpysrc,hbsstand
       /undefine JsonParserOptions
       /undefine HbsSbsCtl


      //---------------------------------------------------------
      // Constants
      //---------------------------------------------------------

      //---------------------------------------------------------
      // Stand Alone Fields
      //---------------------------------------------------------

       dcl-ds dsMaintEvent qualified;
         ApplicationNameType int(10);
         ClientIpAddress varchar(25);
         InstitutionId varchar(25);
       //  RequestType varchar(25);
         ChangedBy varchar(25);
         ChangeDate varchar(25);
         EntityType varchar(25);
         EntityId varchar(25);
         Maintenance varchar(25);
         Operation varchar(25);
         Program varchar(25);
         Workstation varchar(25);

         num_ChangedInformationCollection int(10);
         dcl-ds ChangedInformationCollection dim(200);
           FieldName varchar(25);
           OldValue varchar(25);
           NewValue varchar(25);
         end-ds;
         dcl-ds ActivityTracking;
           ActivityId varchar(36) inz('');
           ParentActivityId varchar(36) inz('');
         end-ds;
         dcl-ds AuthenticationUser;
           InternalId varchar(25) inz('');
           InternalSecondaryId varchar(25) inz('');
           UserType int(10) inz(0);
         end-ds;
         dcl-ds EndUser;
           InternalId varchar(25) inz('');
           InternalSecondaryId varchar(25) inz('');
           UserType int(10) inz(0);
         end-ds;
         dcl-ds ProductInformation;
           ProductName varchar(25) inz('');
           FeatureName varchar(25) inz('');
           Version varchar(25) inz('');
         end-ds;
       end-ds;

       dcl-ds MantDS extname('HBMANT_T') qualified template END-DS;

       dcl-ds dsMnt likeds(MantDS) dim(200);

       dcl-ds AcctDta qualified dim(200);
         Acct# char(16);
         ActType char(1);
       END-DS;

       //dcl-ds dsHBSSBSCTL;
       //  d_SBSName char(10);
       //  d_SBSLib char(10);
       //  d_BankLib char(10);
       //  d_FINum char(4);
       //  d_LocalIP char(16);
24001  //  d_CoreID  char(5);
24001  //  d_Misc    char(445);
       //end-ds;

       dcl-ds pJSON based(@pclob);
         pPGUID char(36);
         pAGUID char(36);
sas    //  pclob varchar(32000);
sas      pclob varchar(2000000);
       END-DS;

       //dcl-ds JSONResp;
       //  jPGUID char(36);
       //  jAGUID char(36);
sas    ////  jclob varchar(32000);
sas    //  jclob varchar(2000000);
       //END-DS;

       dcl-ds *n extname('JHAPAR') dtaara (*auto) end-ds;

       dcl-s @pclob pointer;
       dcl-s @rclob pointer;
       dcl-s rc int(10);
       dcl-s forever ind inz(*on);
       dcl-s cmd char(256);
       dcl-s MntRecs int(10);
       dcl-s AcctRecs int(10);
sasn   dcl-s JsonString varchar(32000);
sasn2  dcl-s JsonString2 varchar(32000);
       dcl-s PsdsString varchar(1000) inz('');
sasx   dcl-s oclob varchar(32000);

       //---------------------------------------------------------
       // Entry
       //---------------------------------------------------------
       dcl-pi *N;
         inAGuid char(36) const;
       end-pi;

         Exec SQL
           Set Option
              Commit = *none,
              CloSqlCsr = *endmod,
              Datfmt = *iso;

       *inlr = *on;
       monitor;
         Main();
       on-error;
       endmon;
         // create log for unmoitored error
         // formate psds
       return;


       //----------------------------------------------------------------------
       // Main
       //----------------------------------------------------------------------
       dcl-proc Main;

       dsHBSSBSCTL = hbstools_GetDataArea('HBSSBSCTL': '*LIBL');

       if d_LocalIP = *blanks;
         d_LocalIP = '127.0.0.1';
       endif;

       If d_FINum = *blanks;
         d_FINum = '9999';
       endif;

       Exec SQL
         Declare MaintCSR cursor for
           Select *
           From HBMANT_T
           where jhguid = :inAGUID;

         clear dsMnt;

            //   Main do loop
           dow (forever);
             // Open Files
             if (OpenFiles() <> 0);
               hbstools_Actvty(pPGUID:pAGUID:550021:
                               'Error Opening HBMANT_T');
               leave;
             endif;

             If Format_Request() <> 0;        // got good request
               hbstools_Actvty(pPGUID:pAGUID:550039:
                               'Error building request');

             else;

               exec sql
                 insert into hbstran
                   (htpguid, htaguid, htsndsts, htpname, httype, htsndhdr)
                 values
                   (:inAGuid, :inAGuid, 'N', 'HBSCMEVT', 'OUTBOUND',
                    '/Jha.Event/api/v1/maintenance');

               hbstools_WriteSendData(hsaguid
                                :JsonString);

       //        exec sql
       //          insert into hbssndd (hsaguid, hsseq, hsdata)
       //                      values (:inAGuid, 1, trim(:JsonString));
       //
             endif;

             leave;

             //  End Main do loop
           enddo;

         rc = CloseFiles();


       end-proc;

      //---------------------------------------------------------
      // CloseFiles - Close Service files opened for use
      //---------------------------------------------------------
        dcl-proc CloseFiles;
          dcl-pi *n int(10) end-pi;

          Monitor;
            if (%open(hbmant_t));
              cmd = 'DLTOVR FILE(hbmant_t)';
              rc  = system(cmd);
              close(e) hbmant_t;
            endif;

            Exec SQL
              Close MaintCsr;

          on-error *all;
            return -1;
          endmon;

          return 0;

        end-proc;

      //---------------------------------------------------------
      // OpenFiles - Open Service files for use
      //---------------------------------------------------------
        dcl-proc OpenFiles;
          dcl-pi *n int(10) end-pi;

          dcl-s errind ind;

          errind = *off;

          monitor;
            if not %open(hbmant_t);
              cmd = 'OVRDBF FILE(hbmant_t) WAITRCD(*IMMED)';
              rc  = system(cmd);
              open(e) hbmant_t;
              if %error;
                errind = *on;
              endif;
            endif;

            Exec SQL
              Open MaintCsr;

          on-error *all;
            errind = *on;
          endmon;

          if errind = *on;
            return -1;
          else;
            return 0;
          ENDIF;

          return 0;


        end-proc;

      // ------------------------------------------------------- //
      //  Edt_EvntName - Remove spaces and capitalize first
      //                position after removed space
      // ------------------------------------------------------- //

       dcl-proc Edt_EvntName;
         dcl-pi *n varchar(80);
           in_evntdsc char(80) const;
         END-PI;

         dcl-s wCapNext ind;
         dcl-s wLen packed(2);
         dcl-s wIndx packed(2);
         dcl-s wResult varchar(80);

         dcl-c upper const('ABCDEFGHIJKLMNOPQRSTUVWXYZ');
         dcl-c lower const('abcdefghijklmnopqrstuvwxyz');

         wLen = %len(%trim(in_evntdsc));
         wCapNext = *off;
         wIndx = 1;
         wResult = *blanks;

         Dou wIndx > wLen;
           if %subst(in_evntdsc:wIndx:1) <> *blanks;
             if wCapNext = *off;
               wResult = %trim(wResult) + %subst(in_evntdsc:wIndx:1);
             else;
               wResult = %trim(wResult) +
                         %xlate(lower:upper:%subst(in_evntdsc:wIndx:1));
             ENDIF;

             wCapNext = *off;
           else;
             wCapNext = *on;
           ENDIF;

           wIndx += 1;

         ENDDO;

         return wResult;

       END-PROC;


      //---------------------------------------------------------
      //  Format_Request - Create Event Request to be sent
      //---------------------------------------------------------
        dcl-proc Format_Request;
          dcl-pi *n int(10);
          end-pi;

          dcl-s wIndx int(10);

sasn      dcl-s JsonPtr pointer;
sasn      dcl-s ActivityTrackingPtr pointer;
sasn      dcl-s AuthenticationUserPtr pointer;
sasn      dcl-s EndUserPtr pointer;
sasn      dcl-s ProductInformationPtr Pointer;
sasn      dcl-s ChangedInformationPtr pointer;
sasn      dcl-s ChangedMoreInformationPtr pointer;
sasn      dcl-s ChangesPtr pointer dim(200);
sasn      dcl-s MoreChangesPtr pointer dim(200);

sasn      dcl-s jsonMsg varchar(50);
sasn      dcl-s TempPtr pointer;
sasn2     dcl-s handle char(1);
sasn2     dcl-s myPointer pointer;

          Dow Get_Maint = 0;

            If MntRecs = 0;
              leave;
            else;
              wIndx = 1;
            endif;

            If wIndx = 1;
              oclob = '{"ChangedBy":"' +
                      %trim(dsMnt(wIndx).jhmuid) + '",' +
                      '"ChangeDate":"'  + %trim(%char(%timestamp())) + '",' +
                      '"EntityType":"CM ID Change",' +
                      '"EntityID":"' + %trim(%editc(dsMnt(wIndx).jhmact:'Z')) +
                      '","Maintenance":"NT/Banno Host",' +
                      '"ChangedInformation":{';


sasn2
sasn2  //     ------------------------------------------
sasn2       dsMaintEvent.ApplicationNameType = 29;
sasn2       dsMaintEvent.ClientIpAddress = %trim(d_LocalIP);
sasn2       dsMaintEvent.InstitutionId = %trim(d_FINum);
sasn2  //     dsMaintEvent.RequestType = 1;
sasn2
sasn2       dsMaintEvent.ChangedBy = %trim(dsMnt(wIndx).jhmuid);
sasn2       dsMaintEvent.ChangeDate = %trim(%char(%timestamp()));
sasn2       dsMaintEvent.EntityType = 'CM ID Change';
sasn2       dsMaintEvent.EntityId = %trim(%editc(dsMnt(wIndx).jhmact:'Z'));
sasn2       dsMaintEvent.Maintenance = 'NT/Banno Host';
sasn2       dsMaintEvent.Operation = %trim(dsMnt(wIndx).jhcrud);
sasn2       dsMaintEvent.Program = %trim(dsMnt(wIndx).jhmpgm);
sasn2       dsMaintEvent.Workstation = %trim(dsMnt(wIndx).jhmwid));
sasn2
sasn2       dsMaintEvent.ActivityTracking.ActivityId = %trim(inAGUID);
sasn2       dsMaintEvent.ActivityTracking.ParentActivityId = %trim(inAGUID);
sasn2
sasn2       dsMaintEvent.AuthenticationUser.InternalId =
sasn2         %trim(%editc(dsMnt(wIndx).jhmact:'Z'));
sasn2       dsMaintEvent.AuthenticationUser.InternalSecondaryId = '';
sasn2       dsMaintEvent.AuthenticationUser.UserType = 2;
sasn2
sasn2       dsMaintEvent.EndUser.InternalId =
sasn2         %trim(%editc(dsMnt(wIndx).jhmact:'Z'));
sasn2       dsMaintEvent.EndUser.InternalSecondaryId = '';
sasn2       dsMaintEvent.EndUser.UserType = 2;
sasn2
sasn2       dsMaintEvent.ProductInformation.ProductName = 'NT/Banno';
sasn2       dsMaintEvent.ProductInformation.Featurename = 'EventTracking';
sasn2       dsMaintEvent.ProductInformation.Version = %trim(jharel);
sasn2

sasn2  //     ------------------------------------------
sasn          JsonPtr = json_NewObject();
sasn          json_SetStr(JsonPtr: 'ChangedBy': %trim(dsMnt(wIndx).jhmuid));
sasn          json_SetStr(JsonPtr: 'ChangedDate': %trim(%char(%timestamp())));
sasn          json_SetStr(JsonPtr: 'EntityType': 'CM ID Change');
sasn          json_SetStr(JsonPtr
sasn                :'EntityID': %trim(%editc(dsMnt(wIndx).jhmact:'Z')));
sasn          json_SetStr(JsonPtr: 'Maintenance': 'NT/Banno Host');
sasn          json_SetStr(JsonPtr: 'Operation': %trim(dsMnt(wIndx).jhcrud));
sasn          json_SetStr(JsonPtr: 'Program': %trim(dsMnt(wIndx).jhmpgm));
sasn          json_SetStr(JsonPtr: 'WorkStation': %trim(dsMnt(wIndx).jhmwid));
sasn          json_SetInt(JsonPtr: 'ApplicationNameType': 29);
sasn          json_SetStr(JsonPtr: 'ClientIPAddress': %trim(d_LocalIP) );
sasn          json_SetStr(JsonPtr: 'InstitutionId': %trim(d_FINum));
sasn
sasn          ActivityTrackingPtr = json_NewObject();
sasn          json_SetStr(ActivityTrackingPtr
sasn                :'ActivityId': %trim(inAGUID));
sasn          json_SetStr(ActivityTrackingPtr
sasn                :'ParentActivityId': %trim(inAGUID));
sasn
sasn          AuthenticationUserPtr = json_NewObject();
sasn          json_SetStr(AuthenticationUserPtr
sasn                :'InternalId'
sasn                :%trim(%editc(dsMnt(wIndx).jhmact:'Z')));
sasn          json_SetStr(AuthenticationUserPtr
sasn                :'InternalSecondaryId'
sasn                :%trim(dsMnt(wIndx).jhcusr));
sasn          json_SetInt(AuthenticationUserPtr: 'UserType': 2);
sasn
sasn          EndUserPtr = json_NewObject();
sasn          json_SetStr(EndUserPtr: 'InternalId'
sasn              :%trim(%editc(dsMnt(wIndx).jhmact:'Z')));
sasn          json_SetStr(EndUserPtr: 'InternalSecondaryId'
sasn              :%trim(dsMnt(wIndx).jhcusr));
sasn          json_SetInt(EndUserPtr: 'UserType': 2);
sasn
sasn          ProductInformationPtr = json_NewObject();
sasn          json_SetStr(ProductInformationPtr
sasn                :'ProductName': 'NT/Banno');
sasn          json_SetStr(ProductInformationPtr
sasb                :'FeatureName': 'EventTracking');
sasn          json_SetStr(ProductInformationPtr
sasn                :'Version': %trim(jharel));
sasn
sasn          json_SetValue(JsonPtr
sasn                       :'ActivityTracking'
sasn                       :ActivityTrackingPtr
sasn                       :json_OBJMOVE);
sasn
sasn          json_SetValue(JsonPtr
sasn                       :'AuthenticationUser'
sasn                       :AuthenticationUserPtr
sasn                       :json_OBJMOVE);
sasn
sasn          json_SetValue(JsonPtr
sasn                       :'EndUser'
sasn                       :EndUserPtr
sasn                       :json_OBJMOVE);
sasn
sasn          json_SetValue(JsonPtr
sasn                       :'ProductInformation'
sasn                       :ProductInformationPtr
sasn                       :json_OBJMOVE);
sasn
sasn          JsonString = json_asJsonText(JsonPtr);

              ChangedInformationPtr = json_newObject();

            endif;

            for wIndx = 1 to MntRecs;
sasn2  //---------------------------
sasn2       // move this to outside the loop - so it's only set once
sasn2       dsMaintEvent.num_ChangedInformationCollection = wIndx;
sasn2       dsMaintEvent.ChangedInformationCollection(wIndx).FieldName =
sasn2         %trim(Edt_EvntName(dsMNT(wIndx).jhmfld));
sasn2       dsMaintEvent.ChangedINformationCollection(wIndx).OldValue =
sasn2         %trim(dsMnt(wIndx).jhmold);
sasn2       dsMaintEvent.ChangedInformationCollection(wIndx).NewValue =
sasn2         %trim(dsMnt(wIndx).jhmnew);
sasn2  //---------------------------

sasn          ChangesPtr(wIndx) = json_newObject();
sasn
sasn          json_SetStr(ChangesPtr(wIndx)
sasn                     :'OldValue'
sasn                     :%trim(dsMnt(wIndx).jhmold));
sasn          json_SetStr(ChangesPtr(wIndx)
sasn                   :'NewValue'
sasn                   :%trim(dsMnt(wIndx).jhmnew));
sasn          json_SetValue(ChangedInformationPtr
sasn                       :%trim(Edt_EvntName(dsMNT(wIndx).jhmfld))
sasn                       :ChangesPtr(wIndx)
sasn                       :json_OBJMOVE);

       //       TempPtr = ChangesPtr(wIndx);
sasn
sasn          JsonString = json_asJsonText(ChangedInformationPtr);

       //       if json_error(TempPtr);
       //         jsonMsg = json_message(TempPtr);
       //         json_dump(TempPtr);
       //       endif;
sasn

              oclob = %trim(oclob) + '"' +
                           %trim(Edt_EvntName(dsMNT(wIndx).jhmfld)) +
                           '":{"OldValue":"' +  %trim(dsMnt(wIndx).jhmold) +
                           '","NewValue":"' + %trim(dsMnt(wIndx).jhmnew) +
                           '"}';

              If windx < MntRecs ;
                oclob = %trim(oclob) + ',';
              else;
                oclob = %trim(oclob) + '},';
              endif;

            endfor;

sasn        json_SetValue(JsonPtr
sasn                     :'ChangedInformation'
sasn                     :ChangedInformationPtr
sasn                     :json_OBJMOVE);
sasn          JsonString = json_asJsonText(JsonPtr);

            windx = 1;

25001       if dsMnt(wIndx).jhcrud = 'DELETE';
sasn          ChangedMoreInformationPtr = json_newObject();

25001         oclob = %trim(oclob) + '"ChangedMoreInformation":[';

25001         for wIndx = 1 to MntRecs;

sasn          MoreChangesPtr(wIndx) = json_newObject();
sasn
sasn          json_SetStr(MoreChangesPtr(wIndx)
sasn                     :'Key'
sasn                     :%trim(Edt_EvntName(dsMNT(wIndx).jhmfld)));
sasn          json_SetStr(MoreChangesPtr(wIndx)
sasn                     :'OldValue'
sasn                     :%trim(dsMnt(wIndx).jhmold));
sasn          json_SetStr(MoreChangesPtr(wIndx)
sasn                   :'NewValue'
sasn                   :%trim(dsMnt(wIndx).jhmnew));
sasn          json_SetValue(ChangedMoreInformationPtr
sasn                       :%trim(Edt_EvntName(dsMNT(wIndx).jhmfld))
sasn                       :MoreChangesPtr(wIndx)
sasn                       :json_OBJMOVE);

sasn
sasn          JsonString = json_asJsonText(ChangedMoreInformationPtr);

25001           oclob = %trim(oclob) + '{"Key":"' +
25001                   %trim(Edt_EvntName(dsMNT(wIndx).jhmfld)) +
25001                   '","Value":{"OldValue":"' +
25001                   %trim(dsMnt(wIndx).jhmold) +
25001                   '","NewValue":"' + %trim(dsMnt(wIndx).jhmnew) +
25001                      '"}}';

25001           If windx < MntRecs ;
25001             oclob = %trim(oclob) + ',';
25001           else;
25001             oclob = %trim(oclob) + '],';
25001           endif;

25001         endfor;
sasn        json_SetValue(JsonPtr
sasn                     :'ChangedMoreInformation'
sasn                     :ChangedMoreInformationPtr
sasn                     :json_OBJMOVE);
sasn          JsonString = json_asJsonText(JsonPtr);

sasn          for wIndx = 1 to MntRecs;
sasn            json_delete(MoreChangesPtr(wIndx));
sasn          endfor;

25001       ENDIF;

25001  //     wIndx = 1;

            oclob = %trim(oclob) +
                    '"Operation":"' + %trim(dsMnt(wIndx).jhcrud) +
                    '","Program":"' + %trim(dsMnt(wIndx).jhmpgm) + '",';
       //
       //     If AcctRecs > 0;
       //       oclob = %trim(oclob) + ',"SupplementalInformation":{';
       //     endif;
       //
       //     for wIndx = 1 to AcctRecs;
       //
       //       oclob = %trim(oclob) + 'AdditionalProp' +
       //                  %char(%editc(wIndx:'Z')) + ':{"AccountNumber":' +
       //                  %trim(AcctDta(wIndx).Acct#) + ',"AccountType":"' +
       //                  %trim(AcctDta(wIndx).ActType) + '"}';
       //
       //       If windx < AcctRecs ;
       //         oclob = %trim(oclob) + ',';
       //       else;
       //         oclob = %trim(oclob) + '},';
       //       ENDIF;
       //
       //     endfor;

            oclob = %trim(oclob) +
                    '"WorkStation":"' + %trim(dsMnt(wIndx).jhmwid) +
                    '","ActivityTracking":{' +
                    '"ActivityId":"' + %trim(inAGUID) + '",' +
                    '"ParentActivityId":"' + %trim(inAGUID) + '"},' +
                    '"ApplicationNameType":29,"AuthenticationUser":{' +
                    '"InternalId":"' +
                    %trim(%editc(dsMnt(wIndx).jhmact:'Z')) + '",' +
                    '"InternalSecondaryId":"' +
                    %trim(dsMnt(wIndx).jhcusr) + '",' +
                    '"UserType":2},' +
                    '"ClientIPAddress":"' + %trim(d_LocalIP) + '",' +
                    '"InstitutionId":"' + %trim(d_FINum) + '",' +
                    '"EndUser":{"InternalId":"' +
                    %trim(%editc(dsMnt(wIndx).jhmact:'Z')) + '",' +
                    '"InternalSecondaryId":"' +
                    %trim(dsMnt(wIndx).jhcusr) + '",' +
                    '"UserType":2},"ProductInformation":{' +
                    '"ProductName":"NT/Banno","FeatureName":"' +
                    'EventTracking","Version":"' + %trim(jharel) +
                     '"}}';

          enddo;

          // this routine will loop through Response data structure

sasn2         DATA-GEN dsMaintEvent %DATA(handle: cDataGenOptions)
sasn2                               %GEN(json_DataGen(myPointer));
sasn2
sasn2         JsonString2 = json_asJsonText16M(myPointer);
sasn
sasn          json_delete(JsonPtr);
sasn          json_delete(ActivityTrackingPtr);
sasn          json_delete(AuthenticationUserPtr);
sasn          json_delete(EndUserPtr);
sasn          json_delete(ProductInformationPtr);
sasn          json_delete(ChangedInformationPtr);
sasn          for wIndx = 1 to MntRecs;
sasn            json_delete(ChangesPtr(wIndx));
sasn          endfor;

          return 0;

        END-PROC;

      //---------------------------------------------------------
      //  Get_Maint - Get Maintenance Records associated with GUID
      //---------------------------------------------------------
        dcl-proc Get_Maint;
          dcl-pi *n int(10) end-pi;

          Exec SQL
            Fetch Next
            From MaintCsr for 200 rows
              Into :dsMNT;

          if sqlstate = '02000' or
            SQLerrd(3) <= 0;
            MntRecs = 0;
            return -1;
          ENDIF;

          If SQLerrd(3) > 0;
            MntRecs = SQLerrd(3);
            return 0;
          ENDIF;

          return 0;

        END-PROC;
       ////---------------------------------------------------------------------
       //// Get Data Area
       ////---------------------------------------------------------------------
       //dcl-proc GetDataArea;
       //  dcl-pi *n char(1024);
       //    p_DataArea char(10) const;
       //    p_Library char(10) const;
       //  end-pi;
       //
       //dcl-s DataString char(1024);
       //
       //clear DataString;
       //
       //exec sql
       //  SELECT DATA_AREA_VALUE into :DataString
       //    FROM TABLE(QSYS2.DATA_AREA_INFO(
       //               DATA_AREA_NAME => :p_DataArea,
       //               DATA_AREA_LIBRARY => :p_Library));
       //
       //return DataString;
       //end-proc;

       //---------------------------------------------------------------------
       // Format Psds
       //---------------------------------------------------------------------
       dcl-proc FormatPsds;
         dcl-pi *n ind;
         end-pi;

       monitor;
         reset PsdsString;

          DATA-GEN mypsds %DATA(PsdsString:
            'doc=string output=clear countprefix=num_')
            %GEN('YAJLDTAGEN');
       on-error;
         PsdsString = 'Error in FormatPsds procedure';
       endmon;
       return *on;
       end-proc;

