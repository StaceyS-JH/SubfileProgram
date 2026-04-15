#!/bin/bash
# ============================================================
# Batch Upload Script for IBM i (Bash/Git Bash/WSL)
# Usage: ./upload-to-ibmi.sh HOSTNAME USERNAME LIBRARY
# ============================================================

IBMI_HOST=$1
IBMI_USER=$2
IBMI_LIB=$3

if [ -z "$IBMI_HOST" ]; then
    echo "Usage: ./upload-to-ibmi.sh HOSTNAME USERNAME LIBRARY"
    echo "Example: ./upload-to-ibmi.sh MYSYSTEM MYUSER MYLIB"
    exit 1
fi

echo "Connecting to $IBMI_HOST as $IBMI_USER..."
echo "Target library: $IBMI_LIB"

# Create FTP command file
cat > ftpcmds.txt <<EOF
$IBMI_USER

quote site namefmt 1
ascii

# Upload RPGLE files
cd /QSYS.LIB/$IBMI_LIB.LIB/QRPGLESRC.FILE
lcd src

EOF

# RPGLE files
for file in JWTCFGM KSCFGM GENKEY GENPKAKEY GENECCKEY JWTGEN GETJWTCFG \
            GETJWACT CRTKSD CRTKS LSTKSRCD SHWPUBKEY EXPRTPEM DER2PEM \
            ECCJWTSIGN PRMKSCFG PRMKSRCD ALGPMT KAPMT OAUTHMENU \
            TESTGETCFG TESTJWACT TESTJWT TESTJWTCFG; do
    echo "put ${file}.RPGLE ${file}.MBR" >> ftpcmds.txt
done

# DSPF files
cat >> ftpcmds.txt <<EOF

cd /QSYS.LIB/$IBMI_LIB.LIB/QDDSSRC.FILE

EOF

for file in JWTCFGD KSCFGD CRTKSD LSTKSRCD SHWPUBKEY PRMKSCFG \
            PRMKSRCD ALGPMT KAPMT OAUTHMENU TESTJWTCFG; do
    echo "put ${file}.DSPF ${file}.MBR" >> ftpcmds.txt
done

# SQL files
cat >> ftpcmds.txt <<EOF

cd /QSYS.LIB/$IBMI_LIB.LIB/QSQLSRC.FILE

EOF

for file in JWTCFG JWTCFGA KSCFG; do
    echo "put ${file}.SQL ${file}.MBR" >> ftpcmds.txt
done

echo "quit" >> ftpcmds.txt

# Execute FTP
ftp -n $IBMI_HOST < ftpcmds.txt

# Cleanup
rm ftpcmds.txt

echo ""
echo "Upload complete!"
echo "Remember to compile on IBM i."
