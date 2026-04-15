@echo off
REM ============================================================
REM Batch Upload Script for IBM i
REM Usage: upload-to-ibmi.bat HOSTNAME USERNAME LIBRARY
REM ============================================================

set IBMI_HOST=%1
set IBMI_USER=%2
set IBMI_LIB=%3

if "%IBMI_HOST%"=="" (
    echo Usage: upload-to-ibmi.bat HOSTNAME USERNAME LIBRARY
    echo Example: upload-to-ibmi.bat MYSYSTEM MYUSER MYLIB
    exit /b 1
)

echo Connecting to %IBMI_HOST% as %IBMI_USER%...
echo Target library: %IBMI_LIB%

REM Create FTP command file
echo %IBMI_USER%> ftpcmds.txt
echo.>> ftpcmds.txt
echo quote site namefmt 1>> ftpcmds.txt
echo ascii>> ftpcmds.txt

REM Upload RPGLE source files
echo.>> ftpcmds.txt
echo cd /QSYS.LIB/%IBMI_LIB%.LIB/QRPGLESRC.FILE>> ftpcmds.txt
echo lcd src>> ftpcmds.txt
echo.>> ftpcmds.txt

REM List of RPGLE files to upload
for %%f in (
    JWTCFGM.RPGLE
    KSCFGM.RPGLE
    GENKEY.RPGLE
    GENPKAKEY.RPGLE
    GENECCKEY.RPGLE
    JWTGEN.RPGLE
    GETJWTCFG.RPGLE
    GETJWACT.RPGLE
    CRTKSD.RPGLE
    CRTKS.RPGLE
    LSTKSRCD.RPGLE
    SHWPUBKEY.RPGLE
    EXPRTPEM.RPGLE
    DER2PEM.RPGLE
    ECCJWTSIGN.RPGLE
    PRMKSCFG.RPGLE
    PRMKSRCD.RPGLE
    ALGPMT.RPGLE
    KAPMT.RPGLE
    OAUTHMENU.RPGLE
    TESTGETCFG.RPGLE
    TESTJWACT.RPGLE
    TESTJWT.RPGLE
    TESTJWTCFG.RPGLE
) do (
    echo put %%f %%~nf.MBR>> ftpcmds.txt
)

REM Upload DSPF source files
echo.>> ftpcmds.txt
echo cd /QSYS.LIB/%IBMI_LIB%.LIB/QDDSSRC.FILE>> ftpcmds.txt
echo.>> ftpcmds.txt

for %%f in (
    JWTCFGD.DSPF
    KSCFGD.DSPF
    CRTKSD.DSPF
    LSTKSRCD.DSPF
    SHWPUBKEY.DSPF
    PRMKSCFG.DSPF
    PRMKSRCD.DSPF
    ALGPMT.DSPF
    KAPMT.DSPF
    OAUTHMENU.DSPF
    TESTJWTCFG.DSPF
) do (
    echo put %%f %%~nf.MBR>> ftpcmds.txt
)

REM Upload SQL source files
echo.>> ftpcmds.txt
echo cd /QSYS.LIB/%IBMI_LIB%.LIB/QSQLSRC.FILE>> ftpcmds.txt
echo.>> ftpcmds.txt

for %%f in (
    JWTCFG.SQL
    JWTCFGA.SQL
    KSCFG.SQL
) do (
    echo put %%f %%~nf.MBR>> ftpcmds.txt
)

echo quit>> ftpcmds.txt

REM Execute FTP
ftp -s:ftpcmds.txt %IBMI_HOST%

REM Cleanup
del ftpcmds.txt

echo.
echo Upload complete!
echo Remember to compile on IBM i:
echo   CRTSQLRPGI / CRTDSPF / RUNSQLSTM
