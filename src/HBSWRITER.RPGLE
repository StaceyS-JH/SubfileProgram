     H/TITLE HBSWRITER - Asynchronous Logger for BSL Subsystem
     H DFTACTGRP(*NO) ACTGRP(*NEW) OPTION(*SRCSTMT : *NODEBUGIO)
     H BNDDIR('JHBIND')

      *----------------------------------------------------------------
      * Program Summary
      *----------------------------------------------------------------
      * This program is submitted as a background job to handle the
      * database logging for HBSRECV and HBSSEND tables. It reads
      * data from a User Space and writes it to the appropriate table,
      * decoupling the logging process from the main transaction path.
      *
      * Parameters:
      *   1. P_GUID (36A): The unique GUID for the transaction. This is
      *      used to locate the User Space and Data Area.
      *   2. P_LOGTYPE (10A): The type of log to perform.
      *      - 'RECV': Write to HBSRECV table.
      *      - 'SEND': Write to HBSSEND table.
      *----------------------------------------------------------------

      *----------------------------------------------------------------
      * File Definitions
      *----------------------------------------------------------------
     FHBSRECV   IF   E           K DISK
     FHBSSEND   IF   E           K DISK

      *----------------------------------------------------------------
      * API Error Data Structure
      *----------------------------------------------------------------
     D ApiError        DS
     D  AeBytesPrv                   10I 0 INZ(%SIZE(ApiError))
     D  AeBytesAvl                   10I 0
     D  AeMsgId                       7A
     D                                1A
     D  AeMsgDta                    256A

      *----------------------------------------------------------------
      * Standalone Fields
      *----------------------------------------------------------------
     D p_Guid          S             36A
     D p_LogType       S             10A

     D UserSpaceName   S             20A
     D DataAreaName    S             20A
     D DataAreaValue   S              3P 0
     D SpcPtr          S               *
     D JsonData        S         2000000A   VARYING BASED(SpcPtr)
     D JsonDataLen     S             10I 0

     D qcmd            S            512A
     D qcmdln          S             15P 5

      *----------------------------------------------------------------
      * User Space API Prototypes
      *----------------------------------------------------------------
     D QUSPTRUS        PR                  ExtPgm('QUSPTRUS')
     D  usName                       20A   Const
     D  usPtr                          *
     D  usError                        *   OPTIONS(*OMIT)

     D QUSDLTUS        PR                  ExtPgm('QUSDLTUS')
     D  usName                       20A   Const
     D  usError                        *   OPTIONS(*OMIT)

      *----------------------------------------------------------------
      * Data Area API Prototypes
      *----------------------------------------------------------------
     D RtvDtaAra       PR                  ExtPgm('QWCRDTAA')
     D  daValue                   32766A
     D  daLen                        10I 0 Const
     D  daQualName                   20A   Const
     D  daStartPos                   10I 0 Const
     D  daDataLen                    10I 0 Const
     D  daError                    1024A

     D ChgDtaAra       PR                  ExtPgm('QWCCDTAA')
     D  daQualName                   20A   Const
     D  daStartPos                   10I 0 Const
     D  daDataLen                    10I 0 Const
     D  daValue                   32766A   Const
     D  daError                    1024A

     D DltDtaAra       PR                  ExtPgm('QDLTDTAA')
     D  daQualName                   20A   Const
     D  daError                        *   OPTIONS(*OMIT)

      *----------------------------------------------------------------
      * QCMDEXC Prototype
      *----------------------------------------------------------------
     D cmdexc          PR                  ExtPgm('QCMDEXC')
     D   cmdtxt                     512A   Const
     D   cmdlngth                    15P 5 Const

      *----------------------------------------------------------------
      * Entry Parameters
      *----------------------------------------------------------------
     C     *ENTRY        PLIST
     C                   PARM                    p_Guid
     C                   PARM                    p_LogType

      /FREE
        // Construct object names from GUID
        UserSpaceName = %TRIM(p_Guid) + 'US';
        DataAreaName  = %TRIM(p_Guid) + 'DA';

        // Get pointer to the User Space
        QUSPTRUS(UserSpaceName : SpcPtr : ApiError);
        IF (ApiError.AeBytesAvl > 0);
          // Log error: Could not get pointer to user space
          *INLR = *ON;
          RETURN;
        ENDIF;

        // Determine the length of the data in the user space
        // (Assuming first 4 bytes of user space store the length)
        JsonDataLen = %INT(%SUBST(JsonData:1:4));

        // Write to the appropriate table
        IF p_LogType = 'RECV';
          WriteToHbsRecv();
        ELSE;
          WriteToHbsSend();
        ENDIF;

        // Signal completion and check for cleanup
        SignalAndCleanup();

        *INLR = *ON;
        RETURN;

       //----------------------------------------------------------------
       // WriteToHbsRecv: Writes the JSON data to the HBSRECV table.
       //----------------------------------------------------------------
       BEGSR WriteToHbsRecv;

         MONITOR;
           EXEC SQL
             INSERT INTO HBSRECV (HRSTAT, HRACTVTID, HRRCVDTA)
             VALUES ('N', :p_Guid,
                     SQLTYPE(CLOB:2000000)
                     %SUBST(JsonData:5:JsonDataLen));

         ON-ERROR;
           // Log SQL error
         ENDMON;

       ENDSR;

       //----------------------------------------------------------------
       // WriteToHbsSend: Writes the JSON data to the HBSSEND table.
       //----------------------------------------------------------------
       BEGSR WriteToHbsSend;

         MONITOR;
           EXEC SQL
             INSERT INTO HBSSEND (HSSTAT, HSACTVTID, HSSNDDTA)
             VALUES ('N', :p_Guid,
                     SQLTYPE(CLOB:2000000)
                     %SUBST(JsonData:5:JsonDataLen));
         ON-ERROR;
           // Log SQL error
         ENDMON;

       ENDSR;

       //----------------------------------------------------------------
       // SignalAndCleanup: Increments the data area counter and
       //                   deletes objects if this is the last job.
       //----------------------------------------------------------------
       BEGSR SignalAndCleanup;

         // Lock, retrieve, increment, and update the data area
         DCL-S daValueNum 3P 0;
         DCL-S daValueChar 3A;

         MONITOR;
           // Retrieve current value
           RtvDtaAra(daValueChar : %SIZE(daValueChar) : DataAreaName :
                     1 : %SIZE(daValueChar) : ApiError);
           IF (ApiError.AeBytesAvl > 0);
             // Log error and exit
             LEAVESR;
           ENDIF;

           daValueNum = %DEC(daValueChar : 3 : 0);
           daValueNum += 1;
           daValueChar = %CHAR(daValueNum);

           // Change the value
           ChgDtaAra(DataAreaName : 1 : %SIZE(daValueChar) :
                     daValueChar : ApiError);
           IF (ApiError.AeBytesAvl > 0);
             // Log error and exit
             LEAVESR;
           ENDIF;

           // Check if we are the last one
           IF daValueNum >= 2;
             // Delete the User Space and Data Area
             qcmd = 'DLTUSRSPC USRSPC(QTEMP/' + %TRIM(UserSpaceName) + ')';
             qcmdln = %len(%trim(qcmd));
             cmdexc(qcmd: qcmdln);

             qcmd = 'DLTDTAARA DTAARA(QTEMP/' + %TRIM(DataAreaName) + ')';
             qcmdln = %len(%trim(qcmd));
             cmdexc(qcmd: qcmdln);
           ENDIF;

         ON-ERROR;
           // Log error
         ENDMON;

       ENDSR;
      /END-FREE
