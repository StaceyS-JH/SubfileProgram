# ============================================================
# Batch Upload Script for IBM i (PowerShell)
# Usage: .\upload-to-ibmi.ps1 -Host HOSTNAME -User USERNAME -Library LIBRARY
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Host,
    
    [Parameter(Mandatory=$true)]
    [string]$User,
    
    [Parameter(Mandatory=$true)]
    [string]$Library,
    
    [Parameter(Mandatory=$false)]
    [string]$Password
)

Write-Host "Connecting to $Host as $User..." -ForegroundColor Green
Write-Host "Target library: $Library" -ForegroundColor Green

# Prompt for password if not provided
if (-not $Password) {
    $SecurePassword = Read-Host "Enter password for $User" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

# Create FTP commands
$ftpCommands = @"
$User
$Password
quote site namefmt 1
ascii

"@

# RPGLE files
$rpgleFiles = @(
    'JWTCFGM', 'KSCFGM', 'GENKEY', 'GENPKAKEY', 'GENECCKEY', 'JWTGEN',
    'GETJWTCFG', 'GETJWACT', 'CRTKSD', 'CRTKS', 'LSTKSRCD', 'SHWPUBKEY',
    'EXPRTPEM', 'DER2PEM', 'ECCJWTSIGN', 'PRMKSCFG', 'PRMKSRCD',
    'ALGPMT', 'KAPMT', 'OAUTHMENU', 'TESTGETCFG', 'TESTJWACT',
    'TESTJWT', 'TESTJWTCFG'
)

$ftpCommands += "cd /QSYS.LIB/$Library.LIB/QRPGLESRC.FILE`r`nlcd src`r`n`r`n"
foreach ($file in $rpgleFiles) {
    $ftpCommands += "put $file.RPGLE $file.MBR`r`n"
    Write-Host "  Queuing: $file.RPGLE → QRPGLESRC($file)" -ForegroundColor Cyan
}

# DSPF files
$dspfFiles = @(
    'JWTCFGD', 'KSCFGD', 'CRTKSD', 'LSTKSRCD', 'SHWPUBKEY',
    'PRMKSCFG', 'PRMKSRCD', 'ALGPMT', 'KAPMT', 'OAUTHMENU', 'TESTJWTCFG'
)

$ftpCommands += "`r`ncd /QSYS.LIB/$Library.LIB/QDDSSRC.FILE`r`n`r`n"
foreach ($file in $dspfFiles) {
    $ftpCommands += "put $file.DSPF $file.MBR`r`n"
    Write-Host "  Queuing: $file.DSPF → QDDSSRC($file)" -ForegroundColor Cyan
}

# SQL files
$sqlFiles = @('JWTCFG', 'JWTCFGA', 'KSCFG')

$ftpCommands += "`r`ncd /QSYS.LIB/$Library.LIB/QSQLSRC.FILE`r`n`r`n"
foreach ($file in $sqlFiles) {
    $ftpCommands += "put $file.SQL $file.MBR`r`n"
    Write-Host "  Queuing: $file.SQL → QSQLSRC($file)" -ForegroundColor Cyan
}

$ftpCommands += "quit`r`n"

# Save commands to temp file
$tempFile = "$env:TEMP\ftpcmds_$((Get-Date).Ticks).txt"
$ftpCommands | Out-File -FilePath $tempFile -Encoding ASCII

Write-Host "`nUploading files..." -ForegroundColor Yellow

# Execute FTP
try {
    ftp -s:$tempFile $Host
    Write-Host "`nUpload complete!" -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Verify files arrived: WRKMBRPDM FILE($Library/QRPGLESRC)" -ForegroundColor White
    Write-Host "  2. Compile display files: CRTDSPF" -ForegroundColor White
    Write-Host "  3. Compile RPG: CRTSQLRPGI" -ForegroundColor White
    Write-Host "  4. Run SQL scripts: RUNSQLSTM" -ForegroundColor White
}
catch {
    Write-Host "Error during upload: $_" -ForegroundColor Red
}
finally {
    # Cleanup
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}
