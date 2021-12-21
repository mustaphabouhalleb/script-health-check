#!/bin/ksh
Linux_MCELOG_Control() {

if [[ -f /usr/sbin/mcelog ]]
then
Count_ERROR=`grep -c "HARDWARE ERROR" /var/log/mcelog`
if [[ $Count_ERROR = 0 ]]
then
DEGFAULTSTATUS=`echo "HWHEALTHOK"`
else
DEGFAULTSTATUS=`echo "HWHEALTHNOK"`
fi
else
DEGFAULTSTATUS=`echo "INSTALLMCELOG"`
fi
}
SOLARIS_FMD_CONTROL() {
DEGFAULTCount=0
if fmadm faulty|/usr/xpg4/bin/grep -q "Fault" >/dev/null 2>&1
then
for i in $(fmadm faulty|/usr/xpg4/bin/grep -w "Fault"|cut -d ':' -f 2,2)
do
DEGFAULTDEV=`echo "$DEGFAULTDEV $i"`
DEGFAULTCount=$(( DEGFAULTCount + 1 ))
done
fi
if [[ $DEGFAULTCount = "0" ]]
then
DEGFAULTSTATUS=`echo "HWHEALTHOK"`
else
DEGFAULTSTATUS=`echo "HWHEALTHNOK"`
fi
}
Solaris_ZFS_Control() {
DEGROOTD=0
if mount | /usr/xpg4/bin/grep "/ "|awk '{print $3}'|/usr/xpg4/bin/grep -q "rpool" >/dev/null 2>&1
then
for i in $(zpool status rpool |grep "d0"|awk '{print $1}')
do
if zpool status rpool |grep $i|/usr/xpg4/bin/grep -vq "ONLINE" >/dev/null 2>&1
then
DEGROOTD=$(( DEGROOTD + 1))
DEGROOTDFi=`echo "$DEGROOTDFi $i"`
fi
done
if [[ $DEGROOTD = "0" ]]
then
DEGROOTDRES=`echo "ROOTOK"`
else
DEGROOTDRES=`echo "ROOTNOK"`
fi
fi
SOLARIS_FMD_CONTROL
}
Solaris_RAID_Control() {
if mount | /usr/xpg4/bin/grep "/ "|awk '{print $3}'|/usr/xpg4/bin/grep -q "s0" >/dev/null 2>&1
then
DEGROOTD=0
for i in $(raidctl -l|grep Volume |cut -d ':' -f 2,2)
do
if raidctl -l $i|awk '{print $3}'|tail -2|/usr/xpg4/bin/grep -vq "GOOD" >/dev/null 2>&1
then
DEGROOTD=$(( DEGROOTD + 1))
DEGROOTDFi=`echo "$DEGROOTDFi $i"`
fi
done
if [[ $DEGROOTD = "0" ]]
then
DEGROOTDRES=`echo "ROOTOK"`
else
DEGROOTDRES=`echo "ROOTNOK"`
fi
fi
SOLARIS_FMD_CONTROL
}
Solaris_SVM_Control() {
if mount | /usr/xpg4/bin/grep "/ "|awk '{print $3}'|grep -v "s0"|/usr/xpg4/bin/grep "/d" >/dev/null 2>&1
then
for i in $(mount | /usr/xpg4/bin/grep "/ "|awk '{print $3}'|grep -v "s0"|/usr/xpg4/bin/grep "/d"|cut -d '/' -f 5,5)
do
if metastat -a $i|grep -w "State:"|sort -u|/usr/xpg4/bin/grep -vq "Okay" >/dev/null 2>&1
then
DEGROOTD=$(( DEGROOTD + 1))
DEGROOTDFi=`echo "$DEGROOTDFi $i"`
fi
done
if [[ $DEGROOTD = "0" ]]
then
DEGROOTDRES=`echo "ROOTOK"`
else
DEGROOTDRES=`echo "ROOTNOK"`
fi
fi
SOLARIS_FMD_CONTROL
}

RED_FileSystem_Control() {
value=79
j=0
DISKUSAGECount=0
for i in $(printf "/\n/usr\n/tmp\n/var\n/opt\n/export/home\n/stand\n/home\n")
do

if [[ -d $i ]]; then
GET_U=`df -k $i| grep % | awk {'print $5 " " $4'} |grep -v 'Use'|cut -d '%' -f1|perl -lane 'print $F[-1]'`
#GET_U=`df -k $i| grep % | awk {'print $5'} | sed 's/%//g'|tail -1`
if [ $GET_U -gt $value ];
then
#echo "$i is greated then $value" >> /tmp/diskusage
DISKUSAGECount=$(( $DISKUSAGECount + 1 ))
DISKUSAGEDEG=`echo $DISKUSAGEDEG $i=%$GET_U`
#printf "%-20s%-20s%-20s%-20s\n" "`hostname`" "Dizin" "$i" "$GET_U" >> /tmp/diskusage
fi
fi
done
if [ $DISKUSAGECount -gt 0 ];
then
DISKUSAGE=`echo DISKUSAGENOK`
else
DISKUSAGE=`echo DISKUSAGEOK`
fi
}

SUN_FileSystem_Control() {
value=79
j=0
DISKUSAGECount=0
for i in $(printf "/\n/usr\n/tmp\n/var\n/opt\n/export/home\n/stand\n/home\n")
do

if [[ -d $i ]]; then
GET_U=`df -k $i| grep % | awk {'print $5'} | sed 's/%//g'|tail -1`
if [ $GET_U -gt $value ];
then
#echo "$i is greated then $value" >> /tmp/diskusage
DISKUSAGECount=$(( $DISKUSAGECount + 1 ))
DISKUSAGEDEG=`echo $DISKUSAGEDEG $i=$GET_U`
#printf "%-20s%-20s%-20s\n" "`hostname`" "$i" "$GET_U" >> /tmp/diskusage
#printf "%-20s%-20s%-20s%-20s\n" "`hostname`" "Dizin" "$i" "$GET_U" >> /tmp/diskusage
(( j=j+1 ))
fi
fi
done
if [ $DISKUSAGECount -gt 0 ];
then
DISKUSAGE=`echo DISKUSAGENOK`
else
DISKUSAGE=`echo DISKUSAGEOK`
fi
}

HP_FileSystem_Control() {
value=79
j=0
DISKUSAGECount=0
for i in $(printf "/\n/usr\n/tmp\n/var\n/opt\n/export/home\n/stand\n/home\n")
do

if [[ -d $i ]]; then
GET_U=`df -k $i| grep % | awk {'print $1'} | sed 's/%//g'|tail -1`
if [ $GET_U -gt $value ];
then
DISKUSAGECount=$(( $DISKUSAGECount + 1 ))
DISKUSAGEDEG=`echo $DISKUSAGEDEG $i=$GET_U`
#echo "$i is greated then $value:Calculated Value:$GET_U" >> /tmp/diskusage
#printf "%-20s%-20s%-20s\n" "`hostname`" "$i" "$GET_U" >> /tmp/diskusage
#printf "%-20s%-20s%-20s%-20s\n" "`hostname`" "Dizin" "$i" "$GET_U" >> /tmp/diskusage
fi
fi
done
if [ $DISKUSAGECount -gt 0 ];
then
DISKUSAGE=`echo DISKUSAGENOK`
else
DISKUSAGE=`echo DISKUSAGEOK`
fi
}
OS=`uname -s`

case "$OS" in
"SunOS")
Solaris_ZFS_Control
Solaris_RAID_Control
Solaris_SVM_Control
SUN_FileSystem_Control
echo ""
printf "%-20s%-20s%-20s%-20s%-20s%-20s\n" "`hostname`" "|Root FileSystem Usage" "|$DISKUSAGE" "|$DISKUSAGEDEG" "]"
printf "%-20s%-20s%-20s%-20s%-20s%-20s\n" "`hostname`" "|Root Disk Control" "|$DEGROOTDRES" "|$DEGROOTDFi" "]"
printf "%-20s%-20s%-20s%-20s%-20s%-20s\n" "`hostname`" "|HardWare Control" "|$DEGFAULTSTATUS" "|$DEGFAULTDEV" "]"
;;
"Linux")
Linux_MCELOG_Control
RED_FileSystem_Control
echo ""
printf "%-20s%-20s%-20s%-20s%-20s%-20s\n" "`hostname`" "|Root FileSystem Usage" "|$DISKUSAGE" "|$DISKUSAGEDEG" "]"
printf "%-20s%-20s%-20s%-20s%-20s%-20s\n" "`hostname`" "|HardWare Control" "|$DEGFAULTSTATUS" "|$DEGFAULTDEV" "]"
;;
"HP-UX")
HP_FileSystem_Control
echo ""
printf "%-20s%-20s%-20s%-20s%-20s%-20s\n" "`hostname`" "|Root FileSystem Usage" "|$DISKUSAGE" "|$DISKUSAGEDEG" "]"
;;
esac
