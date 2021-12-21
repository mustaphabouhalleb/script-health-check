#!/bin/bash 
function sysstat {
echo -e "
#####################################################################
    Health Check Report (CPU,Process,Disk Usage, Memory)
#####################################################################


hostnamectl
Kernel Version   : `uname -r`
Uptime           : `uptime | sed 's/.*up \([^,]*\), .*/\1/'`
Last Reboot Time : `who -b | awk '{print $3,$4}'`

*********************************************************************
CPU Load - > Threshold < 1 Normal > 1 Caution , > 2 Unhealthy 
*********************************************************************
"
MPSTAT=`which mpstat`
MPSTAT=$?
if [ $MPSTAT != 0 ]
then
	echo "Please install mpstat!"
	echo "On RHEL based systems:"
	echo "yum install sysstat"
else
echo -e ""
LSCPU=`which lscpu`
LSCPU=$?
if [ $LSCPU != 0 ]
then
	RESULT=$RESULT" lscpu required to producre acqurate reults"
else
cpus=`lscpu | grep -e "^CPU(s):" | cut -f2 -d: | awk '{print $1}'`
i=0
while [ $i -lt $cpus ]
do
	echo "CPU$i : `mpstat -P ALL | awk -v var=$i '{ if ($3 == var ) print $4 }' `"
	let i=$i+1
done
fi
echo -e "
Load Average   : `uptime | awk -F'load average:' '{ print $2 }' | cut -f1 -d,`

Heath Status : `uptime | awk -F'load average:' '{ print $2 }' | cut -f1 -d, | awk '{if ($1 > 2) print "Unhealthy"; else if ($1 > 1) print "Caution"; else print "Normal"}'`
"
fi
echo -e "
*********************************************************************
                             Process
*********************************************************************

=> Top memory using processs/application

PID %MEM RSS COMMAND
`ps aux | awk '{print $2, $4, $6, $11}' | sort -k3rn | head -n 10`

=> Top CPU using process/application
`top b -n1 | head -17 | tail -11`

*********************************************************************
Disk Usage - > Threshold < 90 Normal > 90% Caution > 95 Unhealthy
*********************************************************************
"
df -Pkh | grep -v 'Filesystem' > /tmp/df.status
while read DISK
do
	LINE=`echo $DISK | awk '{print $1,"\t",$6,"\t",$5," used","\t",$4," free space"}'`
	echo -e $LINE 
	echo 
done < /tmp/df.status
echo -e "

Heath Status"
echo
while read DISK
do
	USAGE=`echo $DISK | awk '{print $5}' | cut -f1 -d%`
	if [ $USAGE -ge 95 ] 
	then
		STATUS='Unhealty'
	elif [ $USAGE -ge 90 ]
	then
		STATUS='Caution'
	else
		STATUS='Normal'
	fi
		
        LINE=`echo $DISK | awk '{print $1,"\t",$6}'`
        echo -ne $LINE "\t\t" $STATUS
        echo 
done < /tmp/df.status
rm /tmp/df.status
TOTALMEM=`free -m | head -2 | tail -1| awk '{print $2}'`
TOTALBC=`echo "scale=2;if($TOTALMEM<1024 && $TOTALMEM > 0) print 0;$TOTALMEM/1024"| bc -l`
USEDMEM=`free -m | head -2 | tail -1| awk '{print $3}'`
USEDBC=`echo "scale=2;if($USEDMEM<1024 && $USEDMEM > 0) print 0;$USEDMEM/1024"|bc -l`
FREEMEM=`free -m | head -2 | tail -1| awk '{print $4}'`
FREEBC=`echo "scale=2;if($FREEMEM<1024 && $FREEMEM > 0) print 0;$FREEMEM/1024"|bc -l`
TOTALSWAP=`free -m | tail -1| awk '{print $2}'`
TOTALSBC=`echo "scale=2;if($TOTALSWAP<1024 && $TOTALSWAP > 0) print 0;$TOTALSWAP/1024"| bc -l`
USEDSWAP=`free -m | tail -1| awk '{print $3}'`
USEDSBC=`echo "scale=2;if($USEDSWAP<1024 && $USEDSWAP > 0) print 0;$USEDSWAP/1024"|bc -l`
FREESWAP=`free -m |  tail -1| awk '{print $4}'`
FREESBC=`echo "scale=2;if($FREESWAP<1024 && $FREESWAP > 0) print 0;$FREESWAP/1024"|bc -l`


printf "Total RAM:\t\t"; grep MemTotal /proc/meminfo| awk '{printf(" %.0f GB\n", $2/1024/1024)}'
printf "Memory free:\t\t"; grep MemFree /proc/meminfo| awk '{printf(" %.0f GB\n", $2/1024/1024)}'
printf "Memory available:\t"; grep MemAvailable /proc/meminfo| awk '{printf(" %.0f GB\n", $2/1024/1024)}'
printf "Memory used:\t\t"; vmstat -s | grep -w "used memory" | awk '{printf(" %.0f GB\n", $1/1024/1024)}'
printf "Swap total:\t\t"; grep SwapTotal /proc/meminfo| awk '{printf(" %.0f GB\n", $2/1024/1024)}'
printf "Swap free:\t\t"; grep SwapFree /proc/meminfo| awk '{printf(" %.0f GB\n", $2/1024/1024)}'
printf "Swap used:\t\t"; vmstat -s | grep -w "used swap" | awk '{printf(" %.0f GB\n", $1/1024/1024)}'
printf "Load average:\t\t"; uptime|grep -o "load average.*"|awk '{print " "$3" " $4" " $5}'
#printf "CPU usage:\t\t"; mpstat -P ALL 1 5 -u | grep "^Average" | sed "s/Average://g" | grep -w "all" | awk '{print $NF}' | awk -F'.' '{print (" "100 -$1 "%")}'

printf "\t\tTop process CPU\n"
ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head

printf "\t\tTop process Memory\n"
ps -eo pid,ppid,cmd,%mem --sort=-%mem | head


num_zomb_proc=$(ps -el | grep -i 'Z' | wc -l)
if [ $num_zomb_proc -gt 0 ]; then
    printf "Number of zombie process:\t"; echo -e "$num_zomb_proc\n"
    printf "Zombie process detail\n"
    zomb_proc=$(ps -el |grep -w 'Z'|awk '{print $4}')
    for i in $(echo "$zomb_proc")
    do 
        ps -o pid,ppid,user,stat,args -p $i
    done
else
    printf "Zombie process status:\t No zombie process\n"
fi

#banner "NTP and synchronization"
#printf "NTP information:\t"; ntpstat | awk 'NR==1 {print $0}'
#printf "NTP lead field:\t\t"; ntpq -c rv | awk 'NR==1 {print $3}'
#printf "NTP reach value:\t"; ntpq -p | awk 'NR==4 {print $7}'

printf "\t\t Time and Date status\n"
timedatectl

printf "\t\tIP information\n"
ifconfig|grep "inet " | column -t
printf "\nNetwork RX-ERR:\t\t"; netstat -i|egrep -v "Iface|statistics"|awk '{sum += $4} END {print sum}'
printf "Network TX-ERR:\t\t"; netstat -i|egrep -v "Iface|statistics"|awk '{sum += $8} END {print sum}'

printf "\t\tBonding information\n"
ip link show | grep "bond.*:" | grep UP | awk -F":" '{print $2}'

printf "\t\tNetwork interface statistics\n"
netstat -i | grep -v ^lo | column -t

printf "\t\tCurrent bandwidth usage\n"
#for interface in $(ip link show | awk '{print $2}' | grep -v '^[0-9]' | grep -v "@"| sed 's/:$//')
#do
#    printf "${interface}: "; sar 1 1 -n DEV | grep ${interface} | grep -v ^Average | tail -1 | awk '{print $6+$7 " Mb"}'
#done

printf "\t\t static routes\n"
route -n

printf "\t\tFilesystem > 75 percent usage:\n\n"
for i in $(df -Ph|egrep -v "^Filesystem|mnt" | awk '{print $5"," $6}' | sort -nr) 
do 
    if [ `echo $i| awk -F "," '{print $1}' | sed 's/%$//'` -gt 75 ]; then
        echo $i| awk -F "," '{if ($1 >=80) print $1 " " $2}'
    else
        echo "All FS are under 75%"
        break
    fi
done


printf "\n\n\t\t HealthChek Summary Report\n\n"
printf "Time UP:\t\t"; uptime|sed 's/.*up \([^,]*\), .*/\1/' | awk '{if ($1 > 0) print "HEALTHY"; else print "WARNING"}'
#printf "CPU Utilization:\t"; mpstat -P ALL 1 5 -u | grep "^Average" | sed "s/Average://g" | grep -w "all" | awk '{print $NF}' | awk -F'.' '{print(100 -$1)}' | awk '{if($1 < 70) print "HEALTHY"; else print "WARNING"}'
printf "Memory Utilization:\t"; vmstat -s | grep -w "used memory" | awk '{printf(" %.0f", $1/1024/1024)}' | awk '{if($1 < 700) print "HEALTHY"; else print "WARNING"}'
printf "SWAP Usage:\t\t"; vmstat -s | grep -w "used swap" | awk '{printf(" %.0f", $1/1024/1024)}' | awk '{if($1 < 20) print "HEALTHY"; else print "WARNING" }'
printf "Load Average:\t\t"; uptime|grep -o "load average.*"|awk '{print  $3}' | sed 's/,$//' | awk '{if($1 <= 15) print "HEALTHY"; else print "WARNING" }'
printf "Zombie Process:\t\t"; if [ $num_zomb_proc -gt 0 ]; then printf "WARNING\n"; else printf "HEALTHY\n"; fi
#printf "NTP Sincronization:\t"; ntpq -p | awk 'NR==4 {print $7}' | awk '{if($1 == 377) print "HEALTHY"; else print "WARNING"}'
printf "Network Errors:\t\t"; netstat -i|egrep -v "Iface|statistics"|awk '{sum += $4;sum += $8} END {print sum}' | awk '{if($1 == 0) print "HEALTHY"; else print "WARNING"}'
printf "Disk Space Usage:\t"; df -Ph|egrep -v "^Filesystem|mnt|tmp" | awk '{print $5,$6}' |sort -n |tail -1 | awk '{if($1 <=80) print "HEALTHY"; else print "WARNING"}'
printf "Message Errors:\t\t"; sudo tail -50 /var/log/messages|egrep -i "warning|error" | wc -l | awk '{if($1 == 0) print "HEALTHY"; else print "WARNING"}'

}
FILENAME="health-`hostname`-`date +%y%m%d`-`date +%H%M`.txt"
sysstat > $FILENAME
echo -e "Reported file $FILENAME generated in current directory." $RESULT
