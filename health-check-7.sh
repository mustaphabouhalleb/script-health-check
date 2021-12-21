#!/bin/bash
#set -x

########################################################################################
############################## about

AUTHOR="Mustapha Bouhalleb"
CONTACT="mbouhall@redhat.com"
DATE="22.12.2021"
VERSION="1.0.8"
#Version history
#1.0.0		mbouhall		first version.
#1.0.1		mbouhall		added warning output to INFO_FILE.
#						changed some ERRORS to WARNINGS
#						removed some checks from tivoli.
#1.0.2		mbouhall		bugfixes.
#1.0.3		mbouhall		added suppot for disabling single tivoli checks.
#1.0.4		mbouhall		changed name to system_healthcheck_linux.sh.
#1.0.5		mbouhall		added suppot for cciss device files.
#						fixed error handling for debug mode.
#1.0.6		mbouhall		 remove some check not important for appcom
#						CHM1 - check zombies
#						CHM2 -check IOwait, INODES
#						CHM3 - support info for appcom, hostname, vlan, customer, frame, img ,uptime
#						CHm15 inodes ussage
#1.0.7		mbouhall		moved appcom check to fucntions.
#						added output for appcom infos in general.
#						added creation of csv file (/tmp/${HOSTNAME}-healtcheck.csv).
#						fixed some bugs.
#1.0.8		mbouhall		added apccom cvs output to stdout. Delimiter is now ;
#

FUNCTION="is used to alert known performance and configuration issues."

########################################################################################
############################## config

# logfile (use "" for none)
LOG_FILE=""

# Infofile
INFO_FILE="/etc/epmf/healthcheck.info"

# healtcheck csv file
HEALTHCHECK_CSV=/tmp/${HOSTNAME}-healtcheck.csv

# mandytory files/links/procs
MANDATORY_FILES_ERROR=""
MANDATORY_FILES_WARNING="/etc/fstab /etc/passwd /etc/shadow /etc/inittab /etc/group /etc/hosts /etc/services /etc/ntp.conf /etc/nsswitch.conf /bin/mount /etc/shells /etc/filesystems"
MANDATORY_FILES_INFO="/etc/resolv.conf"
MANDATORY_LINKS_ERROR=""
MANDATORY_LINKS_WARNING=""
MANDATORY_LINKS_INFO=""
MANDATORY_PROCS_ERROR=""
MANDATORY_PROCS_WARNING="rsyslogd|syslog-ng|syslogd sshd cron|crond"
MANDATORY_PROCS_INFO=""

# invalid SIDS (all this and "")
NOT_VALID_SIDS="S12345 S123456 S1234567 S12345678 S123456789"

# max ntp offset in milliseconds
NTP_MAX_OFFSET="5000"
# min server uptime in seconds
NTP_MIN_SERVER_UPTIME="600"

# procs that could hang because of stale nfs
NFS_PROGS="vgs|lvs|pvs|df|vgdisplay|lvdisplay|netstat|nfshelper|showmount|ls|cd"

# mtu sizes 9000 for storage 1500 for all other
MTU_SIZE="1500"
MTU_SIZE_STORAGE="9000"

# count of vmstat runs for check_paging and check_running_procs
VMSTAT_COUNT="10"

# paging, swap, load, running_procs min/max
MAX_PAGING="5"
MIN_SWAP_FREE_PERCENT="0.2"
MAX_LOAD_PER_CORE="5"
MAX_RUNNPROC_PER_CORE="2"

# minimal free memory in MB
MEM_MIN_FREE="100"

# actual AppCom frame version
# FRAME_RELEASE_MIN="11324"

# default timezone
TIMEZONE="CET-1CEST"

########################################################################################
############################## fixed config

# set $PATH
#export PATH="/bin:/sbin:/usr/bin:/usr/sbin"
declare -x PATH="/bin:/sbin:/usr/local/bin:/usr/bin:/usr/X11R6/bin:/bin:/usr/sbin:/usr/lib/mit/bin:/usr/lib/mit/sbin"

SCRIPT="${0}"
SCRIPT_NAME="$(basename "${SCRIPT}")"
#SCRIPT_DIR=$(cd $(dirname "${SCRIPT}");pwd; cd - >/dev/null)
SCRIPT_SHORTNAME="${SCRIPT_NAME%.sh}"

# nscd/sssd config
NSCD_AUTOSTART_FILES="/etc/autostart.nscd /var/AppCom/etc/autostart.nscd"
NSCD_BIN="/usr/sbin/nscd"
NSCD_PID_FILE="/var/run/nscd/nscd.pid"
NSCD_CONF_FILE="/etc/nscd.conf"
SSSD_BIN="/usr/sbin/sssd"
SSSD_CONF_FILE="/etc/sssd/sssd.conf"
SSSD_PID_FILE="/var/run/sssd.pid"
NSCD_WORKING_COUNT="0"
NSCD_WORKING="0"

# ldap config
LDAP_CONF_FILE="/etc/ldap.conf"
CHECKPROC_BIN="/sbin/checkproc"

# check rpm command
CHECK_RPM_COMMAND="rpm -Va --nofiles"

# mount outputs
MOUNT="$(mount)"
MOUNT_NFS="$(mount -t nfs)"
# ps output
PS_ROOT=$(ps -eu root)
# cpu core count
CPUCORE=$(cat /proc/cpuinfo | grep processor | wc -l)
# uptime in seconds
UPTIME=$(cat /proc/uptime  |awk '{print $1}' |awk -F"." '{print $1}')

SYSLOG="/var/log/messages"

DEBUG="0"
TIVOLI="0"

########################################################################################
############################## functions

func_msg()
{
	# Available msg types:
	# $1								$2
	# LIST								OK,ERROR,FAILED,WARING,MSG_RESULT*,<MESSAGE>
	# INFO,VINFO,ERROR,FAILED,WARING	<MESSAGE>
	# LOG								<MESSAGE>

	MSG_TYPE="$1"
	MSG="$2"
	MSG_CHAR="."
	MSG_FILLUP=" "
	MSG_LISTWITH_MAX="200"
	#MSG_LISTWITH_MAX="80"
	MSG_DEL="\b\b\b\b\b\b\b\b\b\b\b"
	MSG_DATE=$(date '+%b %d %Y %H:%M:%S')

	MSG_TERMWITH=$(tput -T5620 cols); RC=$?
	if [[ "${RC}" != "0" ]]
	then
		MSG_TERMWITH="80"
	fi
	MSG_LISTWITH=$(( ${MSG_TERMWITH} - 12 )) #12 == [   OK   ]
	if (( ${MSG_LISTWITH} < 0 )) || (( ${MSG_LISTWITH} > ${MSG_LISTWITH_MAX} ));then
	        MSG_LISTWITH=${MSG_LISTWITH_MAX}
	fi

	if [[ ${LOG_FILE} != "" ]]; then
		if [[ "${MSG_TYPE}" = "LOG" ]]; then
			echo -e "${MSG}" |sed -e "s/^/${MSG_DATE} ${USER} ${HOSTNAME} [$$] : /g" >> ${LOG_FILE}
			return
		else
			echo -e "${MSG_DATE} ${USER} ${HOSTNAME} [$$] : ${MSG_TYPE} : ${MSG}" >> ${LOG_FILE}
		fi
	fi
	
	if [ "${DEBUG}" -eq "0" ] && [ "${TIVOLI}" -eq "0" ];then
		case ${MSG_TYPE} in
			INFO)           if [[ "${LISTMODE}" = "open" ]]; then
								echo -e "${MSG_DEL}[   \033[1;32mOK\033[0m    ]"
								LISTMODE="closed"
							fi
							echo -e "${MSG_TYPE}    - ${MSG}"
							;;
			VINFO)          if [[ "${VERBOSE}" = "1" ]]; then
								if [[ "${LISTMODE}" = "open" ]]; then
									echo -e "${MSG_DEL}[   \033[1;32mOK\033[0m    ]"
									LISTMODE="closed"
								fi
								echo -e "INFO    - ${MSG}"
							fi
							;;
			ERROR)          if [[ "${LISTMODE}" = "open" ]]; then
								echo -e "${MSG_DEL}[  \033[1;31mERROR\033[0m  ]"
								LISTMODE="closed"
								CHAPTER_FAILED="FAILED"
							fi
							echo -e "${MSG_TYPE}   - ${MSG}"
							;;
			FAILED)			if [[ "${LISTMODE}" = "open" ]]; then
								echo -e "${MSG_DEL}[ \033[1;31mFAILED\033[0m  ]"
								LISTMODE="closed"
								CHAPTER_FAILED="FAILED"
							fi
							echo -e "${MSG_TYPE}   - ${MSG}"
							;;
			WARNING)        if [[ "${LISTMODE}" = "open" ]]; then
								echo -e "${MSG_DEL}[ \033[1;33mWARNING\033[0m ]"
								LISTMODE="closed"
							fi
							echo -e "${MSG_TYPE} - ${MSG}"
							;;
		esac

		if [[ "${MSG_TYPE}" = "LINE" ]]; then
			if [[ ${MSG} != "" ]]; then
				MSG_FILLUP=""
				MSG_BCOUNT=$(( ${MSG_TERMWITH} - 1 ))
				MSG_i=0
				while (( ${MSG_i} < ${MSG_BCOUNT} )); do
					MSG_FILLUP="${MSG_FILLUP}${MSG}"
					MSG_i=$(( ${MSG_i} + 1))
				done
				echo ${MSG_FILLUP}
			else
				echo
			fi
		fi
		
		if [[ "${MSG_TYPE}" = "CHAPTER" ]]; then
			
			MSG_NOBLANK=$(echo "${MSG}" |sed -e 's/ /_/g')
		
			if [[ "${CHAPTER_INFOS}" = "" ]]; then
				CHAPTER_INFOS="func_msg LIST \"${MSG}\""
				XLS="${MSG_NOBLANK}"
			else
				echo
				XLS="${XLS};${CHAPTER_FAILED};${MSG_NOBLANK}"
				CHAPTER_INFOS="${CHAPTER_INFOS}\nfunc_msg LIST ${CHAPTER_FAILED}"
				CHAPTER_INFOS="${CHAPTER_INFOS}\nfunc_msg LIST \"${MSG}\""
			fi
			CHAPTER_FAILED="PASSED"
			echo -e "\033[1;34m${MSG}:\033[0m"
		fi
	
		if [[ "${MSG_TYPE}" = "SUMMARY" ]]; then
			echo -e "\n\033[1;35m${MSG}:\033[0m"
			CHAPTER_INFOS="${CHAPTER_INFOS}\nfunc_msg LIST ${CHAPTER_FAILED}"
			eval "$(echo -e "${CHAPTER_INFOS}")"
			return
		fi
		
		if [[ "${MSG_TYPE}" = "XLS" ]]; then
			echo "${HOSTinfo};${XLS};${CHAPTER_FAILED}" |sed -e 's/PASSED/OK/g'
			return
		fi
		
		if [[ "${MSG_TYPE}" = "LIST" ]] || [[ "${MSG_TYPE}" = "VLIST" && "${VERBOSE}" = "1" ]];then
			if [[ "${LISTMODE}" = "open" ]]; then
				case $MSG in
					OK)             echo -e "${MSG_DEL}[   \033[1;32mOK\033[0m    ]"
									LISTMODE="closed"
									;;
					PASSED)			echo -e "${MSG_DEL}[ \033[1;32mPASSED\033[0m  ]"
									LISTMODE="closed"
									;;
					ERROR)          echo -e "${MSG_DEL}[  \033[1;31mERROR\033[0m  ]"
									LISTMODE="closed"
									;;
					FAILED)          echo -e "${MSG_DEL}[ \033[1;31mFAILED\033[0m  ]"
									LISTMODE="closed"
									;;							
					WARNING)        echo -e "${MSG_DEL}[ \033[1;33mWARNING\033[0m ]"
									LISTMODE="closed"
									;;
					NA)		        echo -e "${MSG_DEL}[   N/A   ]"
									LISTMODE="closed"
									;;
					MSG_RESULT*)	NEW_MSG=$(echo ${MSG} |sed -e 's/MSG_RESULT //')
									MSG_SPACE=$(( 10 - $(echo ${NEW_MSG} |wc -c)))
									if (( "${MSG_SPACE}" < "0" ))
									then
										func_msg LIST OK
										func_msg INFO "Result: ${NEW_MSG}"
									fi
									echo -en "${MSG_DEL}["
									case $MSG_SPACE in
										0) echo -e "${NEW_MSG}]";;
										1) echo -e " ${NEW_MSG}]";;
										2) echo -e " ${NEW_MSG} ]";;
										3) echo -e "  ${NEW_MSG} ] ";;
										4) echo -e "  ${NEW_MSG}  ] ";;
										5) echo -e "   ${NEW_MSG}  ] ";;
										6) echo -e "   ${NEW_MSG}   ] ";;
										7) echo -e "    ${NEW_MSG}   ] ";;
										8) echo -e "    ${NEW_MSG}    ] ";;
									esac
									LISTMODE="closed"
									;;
				esac
			elif [[ "${MSG}" != "OK" ]] && [[ "${MSG}" != "ERROR" ]] && [[ "${MSG}" != "FAILED" ]] && [[ "${MSG}" != "WARNING" ]]; then
				MSG_COUNT=`echo ${MSG} | wc -c`
				MSG_BCOUNT=$(( ${MSG_LISTWITH} - ${MSG_COUNT} - 1 ))
				while (( ${MSG_BCOUNT} < "1" ));do
					MSG_BCOUNT=$((${MSG_BCOUNT} + ${MSG_TERMWITH}))
				done
				MSG_i=0
				while (( ${MSG_i} < ${MSG_BCOUNT} )); do
					MSG_FILLUP="${MSG_FILLUP}${MSG_CHAR}"
					MSG_i=$(( ${MSG_i} + 1))
				done
				echo -en "${MSG}${MSG_FILLUP} [ working ]"
				LISTMODE="open"
			fi
		fi
	elif [[ ${DEBUG} = "1" ]]; then
		echo  "${MSG_TYPE}: ${MSG}" 1>&2
		if [[ "${MSG_TYPE}" = "WARNING" || "${MSG_TYPE}" = "FAILED" || "${MSG_TYPE}" = "ERROR" ]]; then
			TIVOLI_ERROR="1"
		fi
	elif [[ ${TIVOLI} = "1" ]] && [[ "${MSG_TYPE}" = "WARNING" || "${MSG_TYPE}" = "FAILED" || "${MSG_TYPE}" = "ERROR" ]]; then
		echo "${MSG_TYPE};${MSG}"; TIVOLI_ERROR="1"
		if [[ "${MSG_TYPE}" = "WARNING" ]]; then
			echo "${MSG_TYPE};${MSG}" >> "${INFO_FILE}"
		fi
	fi
}

func_summary()
{
func_msg LINE
func_msg LINE
func_msg LINE -
func_msg SUMMARY "Management Summary"
func_msg LINE
func_msg LINE -

if [[ ${APPCOM} = "1" ]]; then 
	CSV_OUTPUT=$(func_msg XLS)
	echo "${CSV_OUTPUT}"
	func_msg LINE -
	func_msg DEBUG "CSV_OUTPUT=[${CSV_OUTPUT}]"
	echo ${CSV_OUTPUT} > ${HEALTHCHECK_CSV}; RC=$?
	if [[ ${RC} = "0" ]]; then
		func_msg INFO "Created file ${HEALTHCHECK_CSV}"
	else
		func_msg INFO "Error while creating file ${HEALTHCHECK_CSV}"
	fi
fi
}

func_getdistro()
{
if [[ -r /etc/redhat-release ]]; then
	grep -qi 'release[      ][      ]*6' /etc/redhat-release && RELEASE="6"
	grep -qi 'release[      ][      ]*5' /etc/redhat-release && RELEASE="5"
	grep -qi 'release[      ][      ]*4' /etc/redhat-release && RELEASE="4"
	DIST="rhel"
elif [[ -r /etc/SuSE-release ]]; then
	grep -qi 'version[      ]*=[    ]*9' /etc/SuSE-release && RELEASE="9"
	grep -qi 'version[      ]*=[    ]*10' /etc/SuSE-release && RELEASE="10"
	grep -qi 'version[      ]*=[    ]*11' /etc/SuSE-release && RELEASE="11"
	DIST="sles"
fi
func_msg debug "DIST=[${DIST}]"
func_msg debug "RELEASE=[${RELEASE}]"

if [[ -z "${RELEASE}" ]] || [[ -z "${DIST}" ]]; then
	func_msg ERROR "Your OS / OS Release is not supported."; exit 1
fi

APPCOM="0"
if [[ -r "/etc/imageversion" ]]; then
	echo "${MOUNT_NFS}" |grep -qw "/cAppCom"; RC=$?
	if [[ "${RC}" = "0" ]]; then
		APPCOM="1"
	fi
fi
func_msg debug "APPCOM=[${APPCOM}]"

}

func_check_file()
{
FILE="$1"
ERROR_MSG_TYPE="$2"
if [ ! -e  "${FILE}" ]; then
	func_msg "${ERROR_MSG_TYPE}" "File [${FILE}] does not exist."
	return 1
else
	func_msg debug "File [${FILE}] exists."
fi
}

func_check_file_readable_not_empty()
{
FILE="$1"
ERROR_MSG_TYPE="$2"
if [ ! -r  "$1" ]; then
	func_msg "${ERROR_MSG_TYPE}" "File [${FILE}] is not readable."
	return 1
else
	func_msg debug "File [${FILE}] is readable."
	if [ ! -s  "$1" ]; then
		func_msg "${ERROR_MSG_TYPE}" "File [${FILE}] is empty."
		return 1
	else
		func_msg debug "File [${FILE}] is not empty."
	fi
fi
}

func_check_file_link()
{
FILE="$1"
ERROR_MSG_TYPE="$2"
if [ ! -l  "${FILE}" ]; then
	func_msg "${ERROR_MSG_TYPE}" "File [${FILE}] is no link."
	return 1
else
	func_msg debug "File [${FILE}] is a link."
fi
}

func_check_proc_is_running()
{
ERROR_MSG_TYPE="$2"
PROC_OK="0"
TMP_PROCS=$(echo ${1} |tr '|' ' ')
func_msg debug "TMP_PROCS=[${TMP_PROCS}]"
for TMP_PROC in ${TMP_PROCS}; do
	echo "${PS_ROOT}" |grep -w ${TMP_PROC} |grep -vq grep && PROC_OK="1"
	func_msg debug "PROC_OK=[${PROC_OK}]"
done
if [[ "${PROC_OK}" = "1" ]]; then
	func_msg debug "Process $1 is running."
else
	func_msg "${ERROR_MSG_TYPE}" "Process $1 is not running."
fi
}

func_get_vmstst()
{
func_msg debug "Running vmstat for ${VMSTAT_COUNT} seconds."
VMSTAT=$(vmstat -n 1 $((${VMSTAT_COUNT}+1)))
}

check_bootloader()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check bootloader config"

if [[ "${APPCOM}" = "1" ]]; then
	func_msg LIST NA
	return
fi

func_msg debug "DIST=[${DIST}]"
func_msg debug "RELEASE=[${RELEASE}]"

if [[ "${APPCOM}" = "1" ]] || [[ "${DIST}" = "sles" && "${RELEASE}" = "9" ]]; then
	func_msg LIST NA
	return
fi
GRUB=$(rpm -qa grub)
if [[ ${GRUB} != "" ]];then
	if [ -f "/boot/grub/menu.lst" ] && [ -f "/boot/grub/device.map" ] ; then
		check_grub_1
	else
		func_msg debug "grub not configured."
	fi
else
	func_msg debug "grub not installed."
fi
func_msg LIST OK
}

check_grub_1()
{
if [ -r  ]; then
	GRUB_CONF=$(cat /boot/grub/menu.lst 2>/dev/null |grep -v ^# |tr -s "[:blank:]" " " |grep -v ^$ |sed -e 's/^ //g' |tr -s "[:blank:]" "%")
else
	func_msg ERROR "can not read /boot/grub/menu.lst"
	return
fi

if [ -r /boot/grub/device.map ]; then
	GRUB_DEV_MAP=$(cat /boot/grub/device.map 2>/dev/null |grep -v ^#)
else
	func_msg ERROR "can not read /boot/grub/device.map"
	return
fi

GROUP_DEFAULT=$(echo "${GRUB_CONF}" |grep "^default" |sed -e 's/default.//')
func_msg debug "GROUP_DEFAULT=[${GROUP_DEFAULT}]"

COUNT="0"
for GRUB_CONF_LINE in ${GRUB_CONF}
do
	if [[ ${TAKE_NEXT} = "1" ]]; then
		if [[ "${GRUB_ROOT}" = "" ]]; then
			GRUB_ROOT=$(echo ${GRUB_CONF_LINE} |grep ^root)
			fi
		if [[ "${GRUB_KERNEL}" = "" ]]; then
			GRUB_KERNEL=$(echo ${GRUB_CONF_LINE} |grep ^kernel)
		fi
		if [[ "${GRUB_INITRD}" = "" ]]; then
			GRUB_INITRD=$(echo ${GRUB_CONF_LINE} |grep ^initrd)
		fi
	fi
	
	TITLE_TMP=$(echo ${GRUB_CONF_LINE} |grep ^title)
	if [[ ${TITLE_TMP} != "" ]]; then
		if (( "${COUNT}" > "${GROUP_DEFAULT}" )); then
			break
		fi
		if [[ ${COUNT} = ${GROUP_DEFAULT} ]]; then
			COUNT=$((${COUNT} +1 ))
			 GRUB_TITLE=${TITLE_TMP}
			func_msg debug "GRUB_TITLE=[${GRUB_TITLE}]"
			TAKE_NEXT="1"
		fi
	fi
done

#check /boot hd
func_msg debug "GRUB_ROOT=[${GRUB_ROOT}]"
GRUB_ROOT_HD=$(echo "${GRUB_ROOT}" |tr -s " ()%" ","|awk -F, '{print $2}')
func_msg debug "GRUB_ROOT_HD=[${GRUB_ROOT_HD}]"
GRUB_ROOT_PART=$(($(echo "${GRUB_ROOT}" |tr -s " ()%" ","|awk -F, '{print $3}')+1))
func_msg debug "GRUB_ROOT_PART=[${GRUB_ROOT_PART}]"
GRUB_BOOT_DEVICE_NO_PART=$(echo "${GRUB_DEV_MAP}" |grep "^(${GRUB_ROOT_HD})" |awk '{print $2}')
func_msg debug "GRUB_BOOT_DEVICE_NO_PART=[${GRUB_BOOT_DEVICE_NO_PART}]"

echo "${GRUB_BOOT_DEVICE_NO_PART}" |grep -q "^/dev/cciss"; GRUB_RC=$?
if [[ ${GRUB_RC} = "0" ]]; then
	func_msg debug "detected a cciss device file add a p to the partition."
	GRUB_BOOT_DEVICE="${GRUB_BOOT_DEVICE_NO_PART}p${GRUB_ROOT_PART}"
else
	GRUB_BOOT_DEVICE="${GRUB_BOOT_DEVICE_NO_PART}${GRUB_ROOT_PART}"
fi
func_msg debug "GRUB_BOOT_DEVICE=[${GRUB_BOOT_DEVICE}]"

BOOT_DEVICE=$(echo "${MOUNT}" |grep -w /boot |awk '{print $1}')
if [[ ${BOOT_DEVICE} = "" ]]; then
	BOOT_DEVICE=$(echo "${MOUNT}" |grep -w / |awk '{print $1}')
fi
func_msg debug "BOOT_DEVICE=[${BOOT_DEVICE}]"
if [[ ${GRUB_BOOT_DEVICE} != "${BOOT_DEVICE}" ]]
then
	func_msg ERROR "Actual boot device is not configured in grub. BOOT_DEVICE=[${BOOT_DEVICE}] GRUB_BOOT_DEVICE=[${GRUB_BOOT_DEVICE}]"
else
	func_msg debug "Boot device is configured."
fi 

#check kernel
func_msg debug "GRUB_KERNEL=[${GRUB_KERNEL}]"
GRUB_KERNEL_FILE="/boot$(echo "${GRUB_KERNEL}" |sed 's/kernel%/kernel=/g' | sed 's/%/\n/g' | grep -w "^kernel" | cut -d "=" -f 2 |sed -e 's%^/boot%%')"
func_msg debug "GRUB_KERNEL_FILE=[${GRUB_KERNEL_FILE}]"
func_check_file "${GRUB_KERNEL_FILE}" ERRORy
NEWEST_KERNEL_FILE=$(ls -ltr /boot/vmlinuz* |grep '^-' |awk '{print $(NF)}' |tail -1)
func_msg debug "NEWEST_KERNEL_FILE=[${NEWEST_KERNEL_FILE}]"
if [[ ${NEWEST_KERNEL_FILE} != "${GRUB_KERNEL_FILE}" ]]
then
	func_msg INFO "Newer Kernel in place. You use [${GRUB_KERNEL_FILE}]. Newer: [${NEWEST_KERNEL_FILE}]"
else
	func_msg debug "Kernel is the newest in /boot/."
fi 

#check rootlv
GRUB_ROOT_LV="$(echo "${GRUB_KERNEL}" | sed 's/%/\n/g' | grep -w "^root" | cut -d "=" -f 2)"
func_msg debug "GRUB_ROOT_LV=[${GRUB_ROOT_LV}]"
if [[ "${GRUB_ROOT_LV}" = "LABEL" ]]; then
	GRUB_ROOT_LABEL="$(echo "${GRUB_KERNEL}" | sed 's/%/\n/g' | grep -w "^root" | cut -d "=" -f 3)"
	if [[ "${GRUB_ROOT_LABEL}" != "/" ]]; then
		func_msg ERROR "root lv in grub config is not /. GRUB_ROOT_LABEL=${GRUB_ROOT_LABEL}"
	fi
else
	ROOT_LV=$(echo "${MOUNT}" |grep -w / |awk '{print $1}')
	func_msg debug "ROOT_LV=[${ROOT_LV}]"
	ROOT_LV_SCR=$(readlink ${ROOT_LV} || echo ${ROOT_LV})
	func_msg debug "ROOT_LV_SCR=[${ROOT_LV_SCR}]"
	GRUB_ROOT_LV_SCR=$(readlink ${GRUB_ROOT_LV} || echo ${GRUB_ROOT_LV})
	func_msg debug "GRUB_ROOT_LV_SCR=[${GRUB_ROOT_LV_SCR}]"
	if [[ ${ROOT_LV_SCR} != "${GRUB_ROOT_LV_SCR}" ]]
	then
		func_msg ERROR "root lv in grub config is not the current root lv. ROOT_LV=${ROOT_LV} GRUB_ROOT_LV=${GRUB_ROOT_LV}"
	else
		func_msg debug "root lv is set."
	fi
fi

#check initrd
func_msg debug "GRUB_INITRD=[${GRUB_INITRD}]"
GRUB_INITRD_FILE="/boot$(echo "${GRUB_INITRD}" |awk -F"%" '{print $2}' |sed -e 's%^/boot%%')"
func_msg debug "GRUB_INITRD_FILE=[${GRUB_INITRD_FILE}]"
func_check_file "${GRUB_INITRD_FILE}" ERROR
}

check_timezone()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check timezone"

if [[ "${APPCOM}" = "1" ]]; then
	func_msg LIST NA
	return
fi

SYSTEM_TIMEZONE=$(strings /etc/localtime |tail -1 |awk -F, '{print $1}')
func_msg debug "SYSTEM_TIMEZONE=[${SYSTEM_TIMEZONE}]"
if [[ ${SYSTEM_TIMEZONE} != "${TIMEZONE}" ]]
then
	func_msg INFO "Timezone not set to ${TIMEZONE}. SYSTEM_TIMEZONE=[${SYSTEM_TIMEZONE}]"
else
	func_msg debug "Timezone not set to ${SYSTEM_TIMEZONE}."
fi 
func_msg LIST OK
}

check_init()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check initlevel"
INIT=$(who -r |awk '{print $2}')
func_msg debug "INIT=[${INIT}]"
INIT_DEFAULT=$(cat /etc/inittab |grep -v ^# |grep -v ^$ |grep initdefault |awk -F: '{print $2}')
func_msg debug "INIT_DEFAULT=[${INIT_DEFAULT}]"
if [[ ${INIT} != "${INIT_DEFAULT}" ]]
then
	func_msg INFO "Init is not the initdefault. INIT=[${INIT}], INIT_DEFAULT=[${INIT_DEFAULT}]"
else
	func_msg debug "Init ok. INIT=[${INIT}]."
fi 
func_msg LIST OK
}

check_mandatory_files()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check mandatory files"
for FILE in ${MANDATORY_FILES_ERROR}; do
	func_check_file_readable_not_empty ${FILE} ERROR
done
for FILE in ${MANDATORY_FILES_WARNING}; do
	func_check_file_readable_not_empty ${FILE} WARNING
done
for FILE in ${MANDATORY_FILES_INFO}; do
	func_check_file_readable_not_empty ${FILE} INFO
done
func_msg LIST OK

func_msg LIST "Check mandatory links"
for LINK in ${MANDATORY_LINKS_ERROR}; do
	func_check_file_readable_not_empty ${LINK} ERROR
done
for LINK in ${MANDATORY_LINKS_WARNING}; do
	func_check_file_readable_not_empty ${LINK} WARNING
done
for LINK in ${MANDATORY_LINKS_INFO}; do
	func_check_file_readable_not_empty ${LINK} INFO
done
func_msg LIST OK
}

check_mandatory_procs()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check mandatory processes"
for PROC in ${MANDATORY_PROCS_ERROR}; do
	func_check_proc_is_running ${PROC} ERROR
done
for PROC in ${MANDATORY_PROCS_WARNING}; do
	func_check_proc_is_running ${PROC} WARNING
done
for PROC in ${MANDATORY_PROCS_INFO}; do
	func_check_proc_is_running ${PROC} INFO
done
func_msg LIST OK
}

check_passwd_consistancy()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check user and group relevant file consistancy"
func_msg debug "running: pwck -rq 2>&1"
PWCK_OUTPUT=$(pwck -rq 2>&1) ; PWCK_RC=$?
if [[ "${PWCK_RC}" != "0" ]]; then
	func_msg WARNING "There are errors in user and group relevant files. Please run [pwck -rq] for details."
	func_msg debug "${PWCK_OUTPUT}"
fi
func_msg LIST OK
}

check_system_id()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check System ID"
func_check_file_readable_not_empty /etc/epmf/tsi_system_info.cfg ERROR || return
SID=$(cat /etc/epmf/tsi_system_info.cfg |grep "^system_id=" |awk -F= '{print $2}')
if [[ "${SID}" = "" ]]; then
	func_msg WARNING "system_id not set in file [/etc/epmf/tsi_system_info.cfg]"
	return
fi
for NOT_VALID_SID in ${NOT_VALID_SIDS}; do
	if [[ "${SID}" = "${NOT_VALID_SID}" ]]; then
		func_msg WARNING "system_id is set to [${SID}] in file [/etc/epmf/tsi_system_info.cfg]"
	fi
done
func_msg LIST OK
}

check_ntp()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check ntp Configuration"

NTP_OUTPUT=$(ntpq -pn 2>/dev/null)
NTP_INFOS=$(echo "${NTP_OUTPUT}" |grep "^\*" |sed -e 's/\*//' |awk '{print $1":"$9}')

# check init
chkconfig --list 2>/dev/null|egrep -q -e 'ntp.*3:on.*5:on' -e 'ntp.*3:Ein.*5:Ein' 2>/dev/null; RC=$?
if [[ ${RC} != "0" ]]
then
        fucn_msg ERROR "ntp is not activated to be started in runlevels 3 or 5."
fi

# check uptime
if (( ${UPTIME} < ${NTP_MIN_SERVER_UPTIME} ))
then
	fucn_msg INFO "OK:Server less than ${NTP_MIN_SERVER_UPTIME} seconds up. UPTIME=[${UPTIME}]"
	return
fi

# check if running
pgrep ntpd >/dev/null 2>&1; RC=$?
if [[ ${RC} != "0" ]]
then
	fucn_msg ERROR "ntpd is not running."
	return
fi

# check output of NTP_INFOS
if [[ "${NTP_INFOS}" != "" ]]
then
	NTP_OFFSET=$(echo ${NTP_INFOS} |awk -F: '{print $2}')
	func_msg debug "${NTP_OFFSET}=[NTP_OFFSET]"
	NTP_OFFSET_SECONDS=$(echo ${NTP_INFOS} |awk -F: '{print $2}' |awk -F. '{print $1}' |sed -e 's/+//' |sed -e 's/-//')
	func_msg debug "${NTP_OFFSET_SECONDS}=[NTP_OFFSET_SECONDS]"
	NTP_SERVER=$(echo ${NTP_INFOS} |awk -F: '{print $1}')
	func_msg debug "${NTP_SERVER}=[NTP_SERVER]"
else
#	echo -e "${NTP_OUTPUT}"
	fucn_msg ERROR "Server is not hooked up to a valid time source. There is no line beginning with \"*\"."
	return
fi

# check if offset is numeric
if [ -z "${NTP_OFFSET_SECONDS}" -o -n "`echo \"$NTP_OFFSET_SECONDS\" | tr -d '[0-9]'`" ]
then
	fucn_msg ERROR "Time offset in not numeric. NTP_OFFSET=[${NTP_OFFSET}]"
	return
fi

# check offset
if (( "${NTP_OFFSET_SECONDS}" > "${NTP_MAX_OFFSET}" ))
then
	fucn_msg ERROR "Time offset to NTP server [${NTP_SERVER}] is more than ${NTP_MAX_OFFSET} milliseconds. NTP_OFFSET=[${NTP_OFFSET}]"
	return
fi

func_msg debug "Time offset to NTP server [${NTP_SERVER}] is less than ${NTP_MAX_OFFSET} milliseconds. NTP_OFFSET=[${NTP_OFFSET}]"
func_msg LIST OK
}

check_rpm_dependencies()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check rpm dependencies"
if [[ ${APPCOM} = "0" ]]; then
	RPM_OUTPUT=$(${CHECK_RPM_COMMAND} 2>&1) ; RPM_RC=$?
	func_msg debug "RPM_RC=[${RPM_RC}]"
	if [[ "${RPM_RC}" != "0" ]]; then
		func_msg WARNING "There are errors in rpm dependencies. Please run [${CHECK_RPM_COMMAND}] for details."
		func_msg debug "${RPM_OUTPUT}"
	fi
else
	func_msg LIST NA
fi
func_msg LIST OK
}

check_default_gw()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check defaul Gateway"
DEFAULT_GWS=$(route -n |grep "^0\.0\.0\.0" |awk '{print $2}')
func_msg debug "DEFAULT_GWS=[${DEFAULT_GWS}]"
for DEFAULT_GW in ${DEFAULT_GWS}; do
	func_msg debug "ping DEFAULT_GW=[${DEFAULT_GW}]"
	PING_RESULT=$(ping -q -W 3 -c 2 "${DEFAULT_GW}"); PING_RC="$?"
	if [[ "${PING_RC}" != "0" ]]; then
		func_msg WARNING "Can not reach default gateway [${DEFAULT_GW}]"
	else
		func_msg debug "ping ok"
	fi
done
func_msg LIST OK
}

check_dns()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check DNS lookup"
DNS_SERVERS=$(cat /etc/resolv.conf |grep ^nameserver |head -1 |awk '{print $2}')
func_msg debug "DNS_SERVERS=[${DNS_SERVERS}]"
for DNS_SERVER in ${DNS_SERVERS}; do
	func_msg debug "lookup DNS_SERVER=[${DNS_SERVER}]"
	if [ -f /usr/bin/host ]; then
		HOST_RESULT=$(host "${DNS_SERVER}"); HOST_RC="$?"
		if [[ "${HOST_RC}" != "0" ]]; then
			func_msg WARNING "Can not lookup your DNS Server [${DNS_SERVER}]"
		else
			func_msg debug "lookup ok"
		fi
	else
		HOST_RESULT=$(ping -q -W 3 -c 2 "${DNS_SERVER}"); HOST_RC="$?"
		if [[ "${HOST_RC}" != "0" ]]; then
			func_msg INFO "Can not ping your DNS Server [${DNS_SERVER}]"
		else
			func_msg debug "ping ok"
		fi
	fi
done
func_msg LIST OK
}

check_nfs()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check NFS Servers"
NFS_SERVERS=$(echo "${MOUNT_NFS}" |awk -F: '{print $1}' |sort -u |tr "[:space:]" " ")
func_msg debug "NFS_SERVERS=[${NFS_SERVERS}]"
for NFS_SERVER in ${NFS_SERVERS}; do
	func_msg debug "ping NFS_SERVER=[${NFS_SERVER}]"
	PING_RESULT=$(ping -q -W 3 -c 2 "${NFS_SERVER}"); PING_RC="$?"
	if [[ "${PING_RC}" != "0" ]]; then
		func_msg ERROR "Can not ping NFS Server [${NFS_SERVER}]"
	else
		func_msg debug "ping ok"
	fi
done
func_msg LIST OK
}

check_hanging_io()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check for hanging io commands"
func_msg debug "NFS_PROGS=[${NFS_PROGS}]"
PS_OUTPUT=$(ps -aeo comm,pid,etime | \
egrep -w "${NFS_PROGS}" | \
awk '
{
  if ( index($3,"-") )
  {
    # hier startzeit zerlegen: "3-12:30:45"
    # --> 3 Tage, 12 einhalb Stunden...
    split($3,arg,"-")

    # in arg[1] stehen jetzt die Tage, die das
    # Kommando schon laeuft

    print $1, $2, $3, arg[1]
    if ( arg[1] > 1 )
      exit 1
  }
}'); PS_RC=$?

func_msg debug "PS_RC=[${PS_RC}]"
func_msg debug "PS_OUTPUT=[${PS_OUTPUT}]"
COMMAND=$(echo ${PS_OUTPUT} |awk '{print $1}')
PID=$(echo ${PS_OUTPUT} |awk '{print $2}')
DAYS=$(echo ${PS_OUTPUT} |awk '{print $4}')
if [[ "${PS_RC}" > "0" ]];then
	func_msg WARNING "Found ${DAYS} days hanging io command COMMAND=[${COMMAND}] PID=[${PID}]" 
fi
func_msg LIST OK
}

check_eth()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check Network Interfaces"
ROOT_FILER=$(echo "${MOUNT_NFS}" |grep " / " |awk -F: '{print $1}' |head -1)
func_msg debug "ROOT_FILER=[${ROOT_FILER}]"
if [ -n "${ROOT_FILER}" ]; then
	for SM in $(ip route show |awk '{print $1}' |awk -F'/' '{print $2}' |grep -v ^$ |sort -u); do
		STORAGE_IF=$(ip route show to ${ROOT_FILER}/${SM} |awk '{print $NF}')
		func_msg debug "STORAGE_IF=[${STORAGE_IF}]"
		if [[ "${STORAGE_IF}" != "" ]]; then
			break
		fi
	done
else
	func_msg debug "No root filer found."
fi

for DEV in $(/sbin/ifconfig | grep encap:Ethernet | cut -d " " -f 1);do
	echo ${DEV} |grep -q ":"; RC=$?
	if [[ ${RC} != "0" ]]; then
	
		IFCONFIG_OUTPUT=$(/sbin/ifconfig ${DEV})
		ETHTOOL_OUTPUT=$(ethtool ${DEV} 2>/dev/null)
	
		LINK_DETECTED=$(ethtool ${DEV} 2>/dev/null |grep -w "Link detected:" |awk '{print $3}')
		func_msg debug "LINK_DETECTED=[${LINK_DETECTED}]"
		
		if [[ "${LINK_DETECTED}" = "yes" ]]; then
		
			if func_is_enabled ${FUNCNAME}-MTU; then
			MTU=$(echo "${IFCONFIG_OUTPUT}" | grep -o MTU:.... | cut -d ":" -f 2)
				if [[ "${DEV}" = "${STORAGE_IF}" ]]; then
					func_msg debug "${DEV} is storage if"
					CHECK_MTU="${MTU_SIZE_STORAGE}"
				else
					func_msg debug "${DEV} is no storage if"
					CHECK_MTU="${MTU_SIZE}"
				fi
				
				if [[ "${MTU}" != "${CHECK_MTU}" ]]; then
					func_msg WARNING "MTU size of ${DEV} is [${MTU}] not [${CHECK_MTU}]"
				else
					func_msg debug "MTU size of ${DEV} is [${MTU}]"
				fi
			fi
			
			SPEED=$(echo "${ETHTOOL_OUTPUT}" |grep -w "Speed:" |awk -F: '{print $2}' |sed -e 's/^ //')
			if [[ "${SPEED}" != "" ]]; then
				func_msg INFO "Network speed of ${DEV} is [${SPEED}]"
			fi
			
			if func_is_enabled ${FUNCNAME}-DUPLEX_MODE; then
				DUPLEX_MODE=$(echo "${ETHTOOL_OUTPUT}" |grep -w "Duplex:" |awk -F: '{print $2}' |sed -e 's/^ //')
				if [[ "${DUPLEX_MODE}" != "Full" ]] && [[ "${DUPLEX_MODE}" != "" ]]; then
					func_msg WARNING "Duplex mode of ${DEV} is [${DUPLEX_MODE}]"
				else
					func_msg debug "Duplex mode of ${DEV} is [${DUPLEX_MODE}]"
				fi
			fi

			PACKETS=$(echo "${IFCONFIG_OUTPUT}" |grep errors | awk '{print $1 $2}' | sed 's/packets/ /g'| tr '\n' ',' |sed -e 's/,$//')
			func_msg debug "Count of network packets from ${DEV} is [${PACKETS}]"		
			
			if func_is_enabled ${FUNCNAME}-COLLISIONS; then
				COLLISIONS=$(echo "${IFCONFIG_OUTPUT}" |grep collisions: |awk '{print $1}' |awk -F: '{print $2}')
				if (( "${COLLISIONS}" > "0" )); then
					func_msg INFO "Collisions found on ${DEV} COLLISIONS=[${COLLISIONS}]"
				else
					func_msg debug "No collisions found on ${DEV} COLLISIONS=[${COLLISIONS}]"
				fi
			fi
			
			if func_is_enabled ${FUNCNAME}-DROPPED; then
				RX_DROPPED=$(echo "${IFCONFIG_OUTPUT}" |grep errors | awk '{print $1 $4}' | sed 's/dropped/ /g'|awk -F: '{print $2}' |head -1)
				TX_DROPPED=$(echo "${IFCONFIG_OUTPUT}" |grep errors | awk '{print $1 $4}' | sed 's/dropped/ /g'|awk -F: '{print $2}' |tail -1)
				DROPPED=$(( ${RX_DROPPED} + ${TX_DROPPED} ))
				if (( "${DROPPED}" > "0" )); then
					func_msg INFO "Dropped packets found on ${DEV} DROPPED=[${DROPPED}]"
				else
					func_msg debug "No dropped packets found on ${DEV} DROPPED=[${DROPPED}]"
				fi
			fi
			
			if func_is_enabled ${FUNCNAME}-NICERR; then
				RX_NICERR=$(echo "${IFCONFIG_OUTPUT}" |grep errors | awk '{print $1 $3}' | sed 's/errors/ /g' |awk -F: '{print $2}' |head -1)
				TX_NICERR=$(echo "${IFCONFIG_OUTPUT}" |grep errors | awk '{print $1 $3}' | sed 's/errors/ /g' |awk -F: '{print $2}' |tail -1)
				NICERR=$(( ${RX_NICERR} + ${TX_NICERR} ))
				if (( "${NICERR}" > "0" )); then
					func_msg INFO "Errors found on ${DEV} NICERR=[${NICERR}]"
				else
					func_msg debug "No errors found on ${DEV} NICERR=[${NICERR}]"
				fi
			fi
		fi
	fi
done
func_msg LIST OK
}

check_load()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check system load"
LOAD_5=$(uptime | awk -F":" '{print $NF}' |awk -F, '{print $2}' |awk -F\. '{print $1}' |sed -e 's/ //')
func_msg debug "LOAD_5=[${LOAD_5}]"
func_msg debug "CPUCORE=[${CPUCORE}]"
func_msg debug "MAX_LOAD_PER_CORE=[${MAX_LOAD_PER_CORE}]"

if (( "${LOAD_5}" > "$(( ${CPUCORE} * ${MAX_LOAD_PER_CORE}))" )); then
	func_msg WARNING "System load is to high [${LOAD_5}]"
else
	func_msg debug "System load ok."
fi

func_msg LIST OK
}

check_paging()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check system paging"
if [ -z "${VMSTAT}" ]; then
	func_get_vmstst
fi

TMP_PAGING=$(echo "${VMSTAT}" |tail -${VMSTAT_COUNT} | awk '{print $7,$8}' | tr '\n' ' ' | sed -e 's/ $/\n/' -e 's/ / + /g' -e "s%\n%) / $(( ${VMSTAT_COUNT} * 2 ))\n%" -e 's/^/(/')
func_msg debug "TMP_PAGING=[${TMP_PAGING}]"

if [[ -x "$(whereis -b bc |awk '{print $2}')" ]]; then
	PAGING=$(echo "scale=2;${TMP_PAGING}" | bc | sed 's/^\./0./')
else
	func_msg WARNING "bc not found. Please install."
	return
fi
#"

func_msg debug "PAGING=[${PAGING}]"
func_msg debug "MAX_PAGING=[${MAX_PAGING}]"

if (( "${PAGING}" > "${MAX_PAGING}" )); then
	func_msg ERROR "System paging is to high. swap in/out per second [${PAGING}]"
else
	func_msg debug "Paging is ok"
fi

func_msg LIST OK
}

check_paging_space()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check system swap"

SWAP_TOTAL=$(cat /proc/meminfo |grep -w "^SwapTotal" |awk '{print $2}')
func_msg debug "SWAP_TOTAL=[${SWAP_TOTAL}]"
SWAP_FREE=$(cat /proc/meminfo |grep -w "^SwapFree" |awk '{print $2}')
func_msg debug "SWAP_FREE=[${SWAP_FREE}]"

SWAP_MIN_FREE=$(echo "${SWAP_TOTAL}" |awk '{printf ("%.0f\n", $1 * '${MIN_SWAP_FREE_PERCENT}' ) }')
func_msg debug "SWAP_MIN_FREE=[${SWAP_MIN_FREE}]"
if (( ${SWAP_FREE} < ${SWAP_MIN_FREE} ));
then
	func_msg ERROR "System swap usage is to high. SWAP_FREE[${SWAP_FREE}] SWAP_TOTAL[${SWAP_TOTAL}]"
else
	func_msg debug "System swap usage ok"
fi
func_msg LIST OK
}

check_running_procs()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check running processes"
if [ -z "${VMSTAT}" ]; then
	func_get_vmstst
fi
TMP_RUNPROC=$(echo "${VMSTAT}" |tail -${VMSTAT_COUNT} | awk '{print $1}' | tr '\n' ' ' | sed -e 's/ $/\n/' -e 's/ / + /g' -e "s%\n%) / ${VMSTAT_COUNT}\n%" -e 's/^/(/')
func_msg debug "TMP_RUNPROC=[${TMP_RUNPROC}]"

if [[ ! -x "$(whereis -b bc |awk '{print $2}')" ]]; then
	func_msg WARNING "bc not found. Please install."
	return
fi
#"

func_msg debug "MAX_RUNNPROC_PER_CORE=[${MAX_RUNNPROC_PER_CORE}]"
func_msg debug "CPUCORE=[${CPUCORE}]"
RUNNPROC=$(echo "scale=2;${TMP_RUNPROC}" | bc | sed 's/^\./0./')
func_msg debug "RUNNPROC=[${RUNNPROC}]"
RUNNPROC_CORE=$(echo "scale=2;${RUNNPROC} / ${CPUCORE}" | bc | sed 's/^\./0./' |cut -d '.' -f 1)
func_msg debug "RUNNPROC_CORE=[${RUNNPROC_CORE}]"

if (( "${RUNNPROC_CORE}" > "${MAX_RUNNPROC_PER_CORE}" )); then
	func_msg WARNING "System has to many running processes per core. RUNNPROC=[${RUNNPROC}]."
else
	func_msg debug "Running processes per core ok."
fi
func_msg LIST OK
}

check_sssd()
{
func_msg LIST "Check sssd"
CHKCONFIG_SSSD_OUTPUT=$(chkconfig --list sssd 2>/dev/null)
func_msg debug "CHKCONFIG_SSSD_OUTPUT=[${CHKCONFIG_SSSD_OUTPUT}]"
echo "${CHKCONFIG_SSSD_OUTPUT}" |grep -q -e ":on" -e ":Ein"; CHKCONFIG_SSSD_RC=$?
if [[ ${CHKCONFIG_SSSD_RC} != "0" ]]
then
	func_msg debug "sssd is not configured."
else
	func_msg debug "sssd is configured."

	# check config files and binaries
	if [[ ! -r "${SSSD_BIN}" ]]; then
		func_msg ERROR "${SSSD_BIN} is not readable."
	else
		func_msg debug "${SSSD_BIN} is readable."
	fi

	if [[ ! -r "${SSSD_CONF_FILE}" ]]; then
		func_msg ERROR "${SSSD_CONF_FILE} is not readable."
	else
		func_msg debug "${SSSD_CONF_FILE} is readable."
	fi

	if [[ ! -x "${SSSD_BIN}" ]]; then
		func_msg ERROR "${SSSD_BIN} is not executable."
	else
		func_msg debug "${SSSD_BIN} is executable."
	fi

	# try to get pid via pidfile if there is no try ps
	if [[ ! -r "${SSSD_PID_FILE}" ]]; then
		func_msg debug "${SSSD_PID_FILE} is not readable."
		SSSD_PID=$(ps -efu root |grep -w "${SSSD_BIN}" |grep -v grep |awk '{print $2}')
	else
		SSSD_PID=$(cat ${SSSD_PID_FILE})
	fi
	func_msg debug "SSSD_PID=[${SSSD_PID}]"

	if [[ ${SSSD_PID} != "" ]]; then
		func_msg debug "Use ps to check process."
		ps -fp ${SSSD_PID} |grep -wq ${SSSD_BIN}; RC_PS="$?"
		
		if [[ ${RC_PS} = "0" ]]
		then
			func_msg debug "ok sssd is running on PID=[${SSSD_PID}]"
		else
			func_msg ERROR "sssd is not running on PID=[${SSSD_PID}]."
		fi

		#check nscd itself via diff of "cache misses on negative entries" in "nscd -g" after id to unknown user
		#NSCD_CACHE_1=$(${NSCD_BIN} -g 2>/dev/null |head -32 |grep "cache misses on negative entries" |awk '{print $1}')
		#func_msg debug "NSCD_CACHE_1=[${NSCD_CACHE_1}]"
		#id user-`date +%s` >/dev/null 2>&1
		#NSCD_CACHE_2=$(${NSCD_BIN} -g 2>/dev/null |head -32 |grep "cache misses on negative entries" |awk '{print $1}')
		#func_msg debug "NSCD_CACHE_2=[${NSCD_CACHE_2}]"

		#if [[ ${NSCD_CACHE_1} != "" ]] && [[ ${NSCD_CACHE_2} != "" ]]; then
		#	if (( "${NSCD_CACHE_1}" >= "${NSCD_CACHE_2}" )); then
		#		echo "FAILED;nscd is not working properly."; NSCD_FAILED="1"
		#	fi
		#else
		#	echo "FAILED;Can not get cache informations (${NSCD_BIN} -g). nscd is maybe not working properly."; NSCD_FAILED="1"
		#fi
		
	else
		func_msg ERROR "sssd is not running."
	fi
fi
func_msg LIST OK
}

check_nscd()
{
func_msg LIST "Check nscd"
if [[ ${APPCOM} = "1" ]];then
	# check if nscd is configured by frame
	func_msg debug "NSCD_AUTOSTART_FILES=[${NSCD_AUTOSTART_FILES}]"
	for NSCD_AUTOSTART_FILE in ${NSCD_AUTOSTART_FILES}; do
		func_msg debug "NSCD_AUTOSTART_FILE=[${NSCD_AUTOSTART_FILE}]"
		if [[ -f "${NSCD_AUTOSTART_FILE}" ]]; then
			func_msg debug "${NSCD_AUTOSTART_FILE} is readable. break..."
			NSCD_CONFIGURED="1"
			func_msg debug "NSCD_CONFIGURED=[${NSCD_CONFIGURED}]"
			break
		fi
	done
else
	CHKCONFIG_NSCD_OUTPUT=$(chkconfig --list nscd 2>/dev/null)
	func_msg debug "CHKCONFIG_NSCD_OUTPUT=[${CHKCONFIG_NSCD_OUTPUT}]"
	echo "${CHKCONFIG_NSCD_OUTPUT}" |grep -q -e ":on" -e ":Ein"; CHKCONFIG_NSCD_RC=$?
	if [[ ${CHKCONFIG_NSCD_RC} != "0" ]]
	then
		NSCD_CONFIGURED="0"
	else
		func_msg debug "nscd configured."
		NSCD_CONFIGURED="1"
	fi
fi

# return with ok if nscd is not configured
if [[ "${NSCD_CONFIGURED}" != "1" ]]; then
	func_msg debug "nscd not configured."
	return
fi

# check config files binaries and pidfile
if [[ ! -r "${NSCD_CONF_FILE}" ]]; then
	fucn_msg ERROR "${NSCD_CONF_FILE} is not readable."
else
	func_msg debug "${NSCD_CONF_FILE} is readable."
fi

if [[ ! -x "${NSCD_BIN}" ]]; then
	fucn_msg ERROR "{NSCD_BIN} is not executable."
else
	func_msg debug "${NSCD_BIN} is executable."
fi

# try to get pid via pidfile if there is no try ps
if [[ ! -r "${NSCD_PID_FILE}" ]]; then
	fucn_msg ERROR "${NSCD_PID_FILE} is not readable."
	NSCD_PID=$(ps -efu root |grep -w "${NSCD_BIN}" |grep -v grep |awk '{print $2}')
else
	NSCD_PID=$(cat ${NSCD_PID_FILE})
fi

func_msg debug "NSCD_PID=[${NSCD_PID}]"

if [[ ${NSCD_PID} != "" ]]; then
	if [ -x ${CHECKPROC_BIN} ]; then
		func_msg debug "Use ${CHECKPROC_BIN} to check process."
		${CHECKPROC_BIN} -p ${NSCD_PID} ${NSCD_BIN}; RC_CHECKPROC="$?"
	else
		func_msg debug "${CHECKPROC_BIN} is not executable use ps to check process."
		ps -fp ${NSCD_PID} |grep -wq ${NSCD_BIN}; RC_CHECKPROC="$?"
	fi
	if [[ ${RC_CHECKPROC} = "0" ]]
	then
		func_msg debug "ok nscd is running on PID=[${NSCD_PID}]"
	else
		func_msg ERROR "nscd is not running on PID=[${NSCD_PID}]."
	fi

	#check nscd itself via diff of "cache misses on negative entries" in "nscd -g" after id to unknown user
	NSCD_CACHE_1=$(${NSCD_BIN} -g 2>/dev/null |head -32 |grep "cache misses on negative entries" |awk '{print $1}')
	func_msg debug "NSCD_CACHE_1=[${NSCD_CACHE_1}]"
	
	while [[ "${NSCD_WORKING}" != "1" ]] && (( "${NSCD_WORKING_COUNT}" < "10" )); do
		NSCD_WORKING_COUNT=$(( ${NSCD_WORKING_COUNT} + 1 ))
		func_msg debug NSCD_WORKING_COUNT=[${NSCD_WORKING_COUNT}]
		func_msg debug NSCD_WORKING=[${NSCD_WORKING}]
		TMP_USER="nouser-$(date +%s)-$$-${NSCD_WORKING_COUNT}"
		func_msg debug TMP_USER=[${TMP_USER}]
		id ${TMP_USER} >/dev/null 2>&1
		#give nscd a chance to set nscd -q output
		sleep 2
		NSCD_CACHE_2=$(${NSCD_BIN} -g 2>/dev/null |head -32 |grep "cache misses on negative entries" |awk '{print $1}')
		func_msg debug "NSCD_CACHE_2=[${NSCD_CACHE_2}]"

		if [[ ${NSCD_CACHE_1} != "" ]] && [[ ${NSCD_CACHE_2} != "" ]]; then
			if (( "${NSCD_CACHE_1}" >= "${NSCD_CACHE_2}" )); then
				func_msg debug "NSCD_CACHE_2 not bigger than NSCD_CACHE_1"
			else
				NSCD_WORKING="1"
			fi
		else
			func_msg ERROR "Can not get cache informations (${NSCD_BIN} -g). nscd is maybe not working properly."
		fi
	done
	if [[ ${NSCD_WORKING} != "1" ]]; then
		func_msg ERROR "nscd is not working properly."
	fi
else
	func_msg ERROR "nscd not running."
fi
	
#	#check nscd itself via diff of "cache misses on negative entries" in "nscd -g" after id to unknown user
#	NSCD_CACHE_1=$(${NSCD_BIN} -g 2>/dev/null |head -32 |grep "cache misses on negative entries" |awk '{print $1}')
#	func_msg debug "NSCD_CACHE_1=[${NSCD_CACHE_1}]"
#	id user-`date +%s` >/dev/null 2>&1
#	NSCD_CACHE_2=$(${NSCD_BIN} -g 2>/dev/null |head -32 |grep "cache misses on negative entries" |awk '{print $1}')
#	func_msg debug "NSCD_CACHE_2=[${NSCD_CACHE_2}]"
#
#	if [[ ${NSCD_CACHE_1} != "" ]] && [[ ${NSCD_CACHE_2} != "" ]]; then
#		if (( "${NSCD_CACHE_1}" >= "${NSCD_CACHE_2}" )); then
#			func_msg ERROR "nscd is not working properly."
#		fi
#	else
#		func_msg ERROR "Can not get cache informations (${NSCD_BIN} -g). nscd is maybe not working properly."
#	fi
#else
#	func_msg ERROR "nscd not running."
#fi

NSCD_G_OUTPUT=$(nscd -g 2>/dev/null)

MAX_THREADS=$(echo "${NSCD_G_OUTPUT}" |grep "maximum number of threads" |awk '{print $1}')
func_msg debug "MAX_THREADS=[${MAX_THREADS}]"
CURR_THREADS=$(echo "${NSCD_G_OUTPUT}" |grep "current number of threads" |awk '{print $1}')
func_msg debug "CURR_THREADS=[${CURR_THREADS}]"

if [[ ${CURR_THREADS} != "" ]] && [[ ${MAX_THREADS} != "" ]]; then
	if (( "$((${CURR_THREADS}+5))" >= "${MAX_THREADS}" )); then
		func_msg WARNING "nscd maximum number of threads almost reached. Please extend."
	else
		func_msg debug "nscd maximum number of threads not reached."
	fi
else
	func_msg ERROR "Can not get thread informations (${NSCD_BIN} -g). nscd is maybe not working properly."
fi

func_msg LIST OK
}

check_nscd_sssd()
{
func_is_enabled $FUNCNAME || return
func_msg debug "find out if you use nscd or sssd" 
if [[ ${DIST} = "sles" ]]; then
	check_nscd
fi

if [[ ${DIST} = "rhel" ]] && (( "${RELEASE}" >= "6" )); then
	check_sssd
fi
}

check_ldap()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check ldap"
# check ldap.conf first because ist needed for check.
if [[ ! -r "${LDAP_CONF_FILE}" ]]; then
	func_msg INFO "${LDAP_CONF_FILE} is not readable. ldap is maybe not configured."
else
	func_msg debug "${LDAP_CONF_FILE} is readable."
	LDAP_CONF=$(cat ${LDAP_CONF_FILE})
	LDAP_USER=$(echo "${LDAP_CONF}" |grep -w ^binddn |awk '{print $2}')
	func_msg debug "LDAP_USER=[${LDAP_USER}]"
	LDAP_PW=$(echo "${LDAP_CONF}" |grep -w ^bindpw |awk '{print $2}')
	func_msg debug "LDAP_PW=[${LDAP_PW}]"
	#this is the ldap check itself via ldapsearch
	if [[ "${LDAP_USER}" != "" ]] && [[ "${LDAP_CONF}" != "" ]]; then
		func_msg debug "ldapsearch -w ${LDAP_PW} -x -D ${LDAP_USER} -b ${LDAP_USER}"
		ldapsearch -w ${LDAP_PW} -x -D ${LDAP_USER} -b ${LDAP_USER} >/dev/null 2>&1; LDAP_SEARCH_RC=$?
		func_msg debug "ldapsearch done..."
		if [[ "${LDAP_SEARCH_RC}" = "0" ]]
		then
			func_msg debug "ldap is accessible."
		else
			func_msg ERROR "ldap is not accessible. RC=[${LDAP_SEARCH_RC}]"
		fi
	else
		func_msg debug "do no ldapsearch LDAP_USER or LDAP_CONF not set."
	fi
fi
func_msg LIST OK
}

check_frame()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check frame release"

if [[ "${APPCOM}" = "1" ]]; then
	if [[ -r "/var/AppCom/etc/frame.AppCom.startup-info" ]]; then
		FRAME_RELEASE=$(cat /var/AppCom/etc/frame.AppCom.startup-info |grep "^\*\*\* frame.AppCom"  |awk -F: '{print $2}' |awk '{print $2}')
		func_msg debug FRAME_RELEASE=[${FRAME_RELEASE}]
		func_msg debug FRAME_RELEASE_MIN=[${FRAME_RELEASE_MIN}]
		
		#if (( "${FRAME_RELEASE_MIN}" > "${FRAME_RELEASE}" ));
		#then
			func_msg INFO "AppCom frame release is [${FRAME_RELEASE}]."
		#fi
	else
		func_msg ERROR "Can not read /var/AppCom/etc/frame.AppCom.startup-info"
	fi
else
	func_msg LIST NA
fi
func_msg LIST OK
}

check_dump()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check dump filesystem"
if [[ "${APPCOM}" = "1" ]]; then
	func_msg LIST NA
	return
fi
if [[ "${DIST}" = "sles" ]]; then
	if [ ! -r "/etc/sysconfig/kdump" ]; then
		func_msg ERROR "Can not read /etc/sysconfig/kdump. No dump configured."
		return
	fi
	DUMP_DIR="$(awk -F= '/^KDUMP_SAVEDIR/  { print $2 }' /etc/sysconfig/kdump |sed -e 's/\"//g' -e 's%file://%%')"
	if [[ -z "${DUMP_DIR}" ]]; then
		func_msg debug "No dump dir set in /etc/sysconfig/kdump"
		DUMP_DIR="/var/crash"
	fi
elif  [[ "${DIST}" = "rhel" ]]; then
	if [ ! -r "/etc/kdump.conf" ]; then
		func_msg ERROR "Can not read /etc/kdump.conf. No dump configured."
		return
	fi
	func_msg debug "awk '/^ext[3|4]/  { print \$2 }' /etc/kdump.conf"
	DUMP_LV="$(awk '/^ext[3|4]/  { print $2 }' /etc/kdump.conf)"
	if [[ "${DUMP_LV}" = "" ]]; then
		func_msg ERROR "Can not find dump FS in /etc/kdump.conf. No dump configured."
		return
	fi
	DUMP_LV=$(readlink ${DUMP_LV} || echo ${DUMP_LV})
	echo "${DUMP_LV}" |grep -qw ^/dev/mapper; DUMP_LV_RC=$?
	if [[ "${DUMP_LV_RC}" != "0" ]]; then
		if [[ -r /dev/mapper ]]; then
			DUMP_LV=$(ls -l /dev/mapper/vg* |grep -w "${DUMP_LV}" |awk '{print $(NF-2)}')
		else
			func_msg WARNING "Can not read /dev/mapper. So dump can not be checked."
			return
		fi
	fi
	func_msg debug DUMP_LV=[${DUMP_LV}]
	DUMP_DIR_TMP=$(echo "${MOUNT}" |grep "${DUMP_LV}" |awk '{print $3}')
	func_msg debug DUMP_DIR_TMP=[${DUMP_DIR_TMP}]
	DUMP_PATH="$(awk '/^path/  { print $2 }' /etc/kdump.conf)"
	func_msg debug DUMP_PATH=[${DUMP_PATH}]
	DUMP_DIR="${DUMP_DIR_TMP}${DUMP_PATH}"
fi
func_msg debug DUMP_DIR=[${DUMP_DIR}]
if [[ ! -d ${DUMP_DIR} ]]; then
	func_msg ERROR "Configured dump filesystem [${DUMP_DIR}] does not exist."
else
	DUMP_FREE_KB=$(df -P "${DUMP_DIR}" |tail -1 |awk '{print $4}')
	func_msg debug DUMP_FREE_KB=[${DUMP_FREE_KB}]
	#MEM_TOTAL_KB=$(cat /proc/meminfo |grep -w "^MemTotal" |awk '{print $2}')
	MEM_TOTAL_KB=$(awk '/^MemTotal/ {print $2}' /proc/meminfo)
	func_msg debug MEM_TOTAL_KB=[${MEM_TOTAL_KB}]
	if (( "${DUMP_FREE_KB}" < "${MEM_TOTAL_KB}")); then
		func_msg WARNING "A full memory dump would not fit in you dump FS [${DUMP_DIR}]."
	else
		func_msg debug "Dump FS size ok."
	fi
fi
func_msg LIST OK
}

check_mem_usage()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check memory usage"
MEM_FREE=$(free -m |grep "buffers/cache" |awk '{print $4}')
func_msg debug MEM_FREE=[${MEM_FREE}]
func_msg debug MEM_MIN_FREE=[${MEM_MIN_FREE}]

if (( "${MEM_FREE}" <= "${MEM_MIN_FREE}" )); then
	func_msg WARNING "Less then ${MEM_FREE}MB memory free"
fi
func_msg LIST OK
}

check_vgs()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check volume group consistency"

if [[ "${APPCOM}" = "1" ]]; then
	func_msg LIST NA
	return
fi

VGCK=$(vgck -v 2>/dev/null); VGCK_RC=$?
if [[ "${VGCK_RC}" != "0" ]]; then
	func_msg ERROR "There is a problem with your VG consistency. See [vgck -v] for details."
else
	func_msg debug "vgck ok"
fi
func_msg LIST OK
}

check_system_errors()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check hardware errors."

if [[ -r "${SYSLOG}" ]]; then
	SYSLOG_TODAY=$(cat "${SYSLOG}" |grep "^$(date +%b' '%e)")
	SYSLOG_HW_CRITICAL=$(echo "${SYSLOG_TODAY}" |grep -w -e "LXMIN" -e "LXMAJ" |grep CRITICAL |cut -d " " -f "6-" |tr -s "[:blank:]" "%")
	if [[ -n "${SYSLOG_HW_CRITICAL}" ]]; then
		for SYSLOG_HW_CRITICAL_MSG in ${SYSLOG_HW_CRITICAL} ; do
			SYSLOG_HW_CRITICAL_MSG=$(echo "${SYSLOG_HW_CRITICAL_MSG}" |tr -s '%' ' ')
			func_msg ERROR $(echo "${SYSLOG_HW_CRITICAL_MSG}" |tr -s "%" " ")
		done
	fi
	SYSLOG_HW_WARNING=$(echo "${SYSLOG_TODAY}" |grep -w -e "LXMIN" -e "LXMAJ" |grep WARNING |cut -d " " -f "6-" |tr -s "[:blank:]" "%")
	if [[ -n "${SYSLOG_HW_WARNING}" ]]; then
		for SYSLOG_HW_WARNING_MSG in ${SYSLOG_HW_WARNING} ; do
			SYSLOG_HW_WARNING_MSG=$(echo "${SYSLOG_HW_WARNING_MSG}" |tr -s '%' ' ')
			func_msg WARNING "${SYSLOG_HW_WARNING_MSG}"
			# |sed -e 's/T/ /')
		done
	fi
else
	func_msg debug "Can not access syslog [${SYSLOG}]."
	func_msg LIST NA
fi
func_msg LIST OK
}

#---------------------------------------------------

#CHM1
check_zombies()
{
func_msg LIST "Check for Zombie process"
zombie=$(top -b -n 1 |head -n 15|grep zombie|awk '{print $10}')
if [ "$zombie" -gt "0" ];
then
	func_msg WARNING "Zombie in process list"
else
	func_msg debug "Zombie ok"
fi
func_msg LIST OK
}


#CHM2
check_IOwait()
{
func_msg LIST "Check IOwait"
MPStat=$(mpstat  3 1|grep Average)
iowait=$(echo "$MPStat"|grep all|awk '{print $6"."}'|awk -F"." '{print $1}')
if [[ "$iowait" -gt "80" ]]; then
	func_msg WARNING "IOWAIT in bigger than 80. iowait=[${iowait}]."
else
	func_msg debug "IOWAIT is less than 80 ok. iowait=[${iowait}]."
fi
func_msg LIST OK
}


#CHM3 appcom information
check_Appcom()
{
if [[ "${APPCOM}" = "1" ]]; then
	#--------LOCATION
	HN=$(uname -n | cut -c 1,2,3); case $HN in ab1) HH=DETMOLDERSTR ;; ab2) HH=WOLBECKERSTR ;; af4) HH=HAHNSTR ;; af6) HH=EQUINIX ;; af7) HH=ESHELTER ;; aff) HH=LURGIALLEE ;; ae4) HH=HAHNSTR ;; ae6) HH=EQUINIX ;; ae7) HH=ESHELTER ;; ak1) HH=BUNSENSTR ;; ak2) HH=KRONSHAGENER ;; ao1) HH=LUEBECKERSTR ;; am1) HH=EIP ;; am2) HH=ALLACH ;; am3) HH=EIP ;; am4) HH=ALLACH ;; al1) HH=MPC ;; al2) HH=LD5 ;; al3) HH=LD5 ;; al4) HH=MPC ;; ac1) HH=CENTURYSQUARE ;; aa1) HH=DC1 ;; aa2) HH=D2A ;; aa3) HH=DC1 ;; aa4) HH=D2A ;; ah1) HH=IC ;; ah2) HH=WESTLANDB ;; ah3) HH=CYRUSONE ;; ah4) HH=WESTLANDB ;; as1) HH=DTC ;; as2) HH=CHAICHEE ;; aj1) HH=SIVEWRIGHT ;; aj2) HH=MEGAWATT_PARK ;; ar3) HH=KREFELD2 ;; ar4) HH=KREFELD2 ;; *) HH=unknown ;; esac
	func_msg INFO "Location is ${HN}."
	#-------VLAN
	interfaceCH=$(cat /var/AppCom/etc/dhcpcd-info |grep INTERFACE|awk -F "'" '{print $2}')
	eth0s=$(ifconfig $interfaceCH|grep "inet addr"|awk -F: '{print $2}'|awk '{print $1}')
	VLAN=$(echo -n "$eth0s"|awk -F"." '{print $2"-60"}'|bc|tr -d "\n";echo -n "$eth0s"|awk -F"." '{print $3}'|tr -d "\n";)
	func_msg INFO "VLAN is ${VLAN}."
	#^106.81.10|106.21.10 ^storageIP|^adminlanIP
#	ADM_STOR=$(
#		echo  "$eth0s"|awk -F"." '{print $1"."$2"."$3".0  "}' ;
#		echo " ";
#		echo -n "$eth0s"|awk -F"." '{print $1"."}'|tr -d "\n ";
#		echo -n "$eth0s"|awk -F"." '{print $2"-60"}'|bc|tr -d " \n ";
#		echo -n "$eth0s"|awk -F"." '{print "."$3".0"}'|tr -d "\n";
#		)
#		#check interface for ADM STOR
#	 ADM_STOR_iface=$(
#		for nets in `echo "$ADM_STOR"`;
#		do ip route get $nets|grep dev|awk '{print $4"|"}'|tr -d " \n "; done)
	#---CUSTOMER
	CUSTOMER=$(df -h /var|grep :|awk -F"/" '{print $4}'|sed "s/_images//g")
	func_msg INFO "Customer is ${CUSTOMER}."
	#---IMGver
	IMGver=$(cat /etc/imageversion|head -n1|tr -d "\n")
	func_msg INFO "Imageversion is ${IMGver}."
	#---FRAMEboot
	FRAME=$(cat /var/AppCom/etc/frame.AppCom.startup-info|grep  "frame.AppCom:"|awk '{print $4}')
	#---UPTIME
	uptimeTIME=$(uptime|awk '{print $3$4}'|tr -d ",")
	func_msg INFO "Uptime is ${uptimeTIME}."
	##--Final needit string
	HOSTinfo=$(echo -n "`uname -n`;Loc;$HH;VLAN;$VLAN;CUST;$CUSTOMER;IMG;$IMGver;FRM;$FRAME;UP;$uptimeTIME"|sed "s/;/-/g")
fi
}


#CHM15
check_Inodes_usage()
{
func_msg LIST "Check Inodes usage"
for fs in $(mount -t nfs 2>/dev/null |awk '{print $3}'|sort|uniq); do
	usageIN=$(df -Pi "$fs" |grep "%"|grep -v Filesystem|awk '{print $5}'|tr -d "%");
	#echo "$fs [$usageIN]"
	if [[ "$usageIN" -gt "95" ]]; then
		func_msg WARNING "Inode usage for FS=[$fs] is higher than 95%. usageIN=[${usageIN}]."
	else
		func_msg debug "Inode usage for FS=[$fs] is lower than 95%. usageIN=[${usageIN}]."
	fi
done
func_msg LIST OK
}


#--------------------------------------------------


check_fscsi()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check fscsi"
func_msg LIST NA
}

check_multipath_io()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check mulitpath io"
if [[ "${APPCOM}" = "0" ]]; then
	if ( lspci 2>/dev/null|grep -qi 'Fibre Channel' ); then
		func_msg debug "Found Fibre Channel in lspci output."
		if [[ "$(lsmod|grep -c '^dm_multipath')" > "0" ]]; then
			func_msg debug "dm_multipath module is running."
			if ( which multipath >/dev/null 2>&1 ); then 
				func_msg debug "multipath command found."
				if [ "$(multipath -dl|wc -l)" -gt 0 ]; then 
					func_msg debug "multipath -dl shows output."
					if ( multipath -dl|egrep ' sd.* \[active\]\['|grep -qv ' \[active\]\[' ); then 
						func_msg LIST OK
					else 
						func_msg ERROR "Not all multipath devices active. See [multipath -dl]."
					fi
				else
					func_msg debug "multipath -dl shows no output."
				fi
			else
				func_msg debug "multipath command not found."
			fi
		else
			func_msg debug "dm_multipath module is not running."
		fi
		if ( which vxdmpadm >/dev/null 2>&1 ); then
			func_msg debug "vxdmpadm command found."
			if [ "$(vxdmpadm listctlr all|grep -v 'OTHER_DISKS$'|grep -c ENABLED)" -gt 0 ]; then
				func_msg debug "vxdmpadm listctlr all shows output."
				for DEVICE in `vxdisk list | grep -v ^DEVICE | awk '{print $1}'`; do
					func_msg debug "DEVICE=[${DEVICE}]"
					if [ "$( vxdisk list ${DEVICE} | grep state=disabled | wc -l)" -gt 0 ]; then
						func_msg ERROR "vxdisk ${DEVICE} in state disabled. See [vxdisk list]."
						return
					else
						func_msg LIST OK
					fi
				done
			else
				func_msg debug "vxdmpadm listctlr all shows no output."
			fi
		else
			func_msg debug "vxdmpadm command not found."
		fi
	else
		func_msg debug "Found no Fibre Channel in lspci output."
	fi
fi
func_msg LIST NA
}

check_iscsi()
{
func_is_enabled $FUNCNAME || return
func_msg LIST "Check iscsi"
if ( pgrep iscsi_eh >&/dev/null ); then
	func_msg debug "iscsi_eh is running."
	if ( which iscsiadm >/dev/null 2>&1 ); then 
		func_msg debug "iscsiadm command found."
		if [ $( iscsiadm --mode node -m session 2>/dev/null | wc -l ) -gt 0 ]; then
			func_msg debug "iscsiadm --mode node -m session shows output."
			if ( egrep -qe '^node.session.timeo.replacement_timeout = 180' /etc/iscsi/iscsid.conf ); then 
				func_msg LIST OK
			else
				func_msg ERROR "Please check /etc/iscsi/iscsid.conf."
			fi
		else
			func_msg debug "iscsiadm --mode node -m session shows no output."
		fi
	else
		func_msg debug "iscsiadm command not found."
	fi
else
	func_msg debug "iscsi_eh is not running."
fi
func_msg LIST NA
}

func_is_enabled()
{
if [[ "${TIVOLI}" = "1" ]] && [[ ${IGNORE_DISABLED} != "1" ]]; then
	FUNCTION_NAME="${1}"
	func_msg debug "FUNCTION_NAME=[${FUNCTION_NAME}]"
	func_msg debug "Check for /etc/epmf/${SCRIPT_SHORTNAME}/${FUNCTION_NAME}.disabled"
	if [ -r /etc/epmf/${SCRIPT_SHORTNAME}/${FUNCTION_NAME}.disabled ]; then
		func_msg debug "${FUNCTION_NAME} disabled via /etc/epmf/${SCRIPT_SHORTNAME}/${FUNCTION_NAME}.disabled"
		return 1
	fi
fi
}


func_disable_check()
{

ENABLED_CHECKS=$(cat "${SCRIPT}" |grep "^check" |grep '()' |grep -v \
-e "check_grub_1" -e "check_sssd" -e "check_nscd" -e "check_load" -e "check_paging" \
-e "check_mem_usage" -e "check_dns" -e "check_system_errors" -e "check_frame" -e "check_ldap" \
|awk -F'(' '{print $1}')
#)
ENABLED_CHECKS=$(echo -e "${ENABLED_CHECKS}\ncheck_eth-MTU\ncheck_eth-DUPLEX_MODE\ncheck_eth-COLLISIONS\ncheck_eth-DROPPED\ncheck_eth-NICERR" |sort)

if [[ ${CHECK_TO_CHANGE} = "" ]];then 
	echo -e "${ENABLED_CHECKS}"
	echo -n "Please select a check to disable: "
	read CHECK_TO_CHANGE
fi
if echo "${ENABLED_CHECKS}" |grep -qw "^${CHECK_TO_CHANGE}$"; then
	if [[ ! -r /etc/epmf/${SCRIPT_SHORTNAME}/${CHECK_TO_CHANGE}.disabled ]]; then
		mkdir -p /etc/epmf/${SCRIPT_SHORTNAME}
		touch /etc/epmf/${SCRIPT_SHORTNAME}/${CHECK_TO_CHANGE}.disabled
		func_msg INFO "Check [${CHECK_TO_CHANGE}] ist now disabled."
	else
		func_msg INFO "Check [${CHECK_TO_CHANGE}] is already disabled."
	fi
else
	func_msg ERROR "Check [${CHECK_TO_CHANGE}] ist not valid."
fi
}

func_enable_check()
{
if [[ ${CHECK_TO_CHANGE} = "" ]];then 
	DISABLED_CHECKS=$(ls -1 /etc/epmf/${SCRIPT_SHORTNAME}/*.disabled 2>/dev/null |awk -F'/' '{print $NF}' |sed -e 's/.disabled//g')
	if [[ "${DISABLED_CHECKS}" = "" ]]; then
		func_msg ERROR "No check disabled."; exit 1
	else
		echo "${DISABLED_CHECKS}"
		echo -en "please try with [-i] option first if problem is fixed.\nPlease select a check to reenable: "
		read CHECK_TO_CHANGE
	fi
fi
if [[ -r /etc/epmf/${SCRIPT_SHORTNAME}/${CHECK_TO_CHANGE}.disabled ]]; then
	rm /etc/epmf/${SCRIPT_SHORTNAME}/${CHECK_TO_CHANGE}.disabled
	func_msg INFO "Check [${CHECK_TO_CHANGE}] ist now enabled."
else
	func_msg ERROR "Check [${CHECK_TO_CHANGE}] ist not disabled."
fi
}


fucn_no_tivoli()
{
if [[ "${TIVOLI}" != "1" ]]; then
	$1
fi
}

func_printhelp()
{
cat <<EOF
 
${SCRIPT_SHORTNAME} version ${VERSION} date ${DATE}
Copyright (C) $(date +"%Y") by T-Systems International GmbH
Author: ${AUTHOR} <${CONTACT}>
 
${SCRIPT_SHORTNAME} ${FUNCTION}

Usage: ${SCRIPT_NAME} [OPTIONS]
 
Options:
	-d		Turning on [d]ebug mode.
	-t		[T]ivoli output mode.
	-m		Show possible [m]essages.
	-v		Print script [v]ersion.
	-h		Print this [h]elp message.
	-s		di[s]able one check for tivoli mode (interactive or -c).
	-e		[e]nable one check for tivoli mode (interactive or -c).
	-c		[C]heck to disable or enable.
	-i		[I]gnore disabled checks.

Please find the full documentation in MyWorkroom.
https://tsi-myworkroom-de.telekom.de/livelink_de/livelink/open/110692717
	
Supported OS releases:
rhel4, rhel5, rhel6
sles9, sles10, sles11

EOF

exit 0
}

########################################################################################
############################## main

while getopts dtmvhsec:i option
do
	case $option in

	d)	DEBUG="1";;
	t)	TIVOLI="1";;
	v)	echo "${SCRIPT_SHORTNAME} version ${VERSION} date ${DATE}";exit 0;;
	m)	grep func_msg ${SCRIPT} |sed -e 's/\t//g' -e 's/func_msg //g' |grep -e ^ERROR -e ^WARNING -e ^FAILED -e ^INFO \
		|sed -e 's/"//g' -e 's/ /;/'|grep -v "NEW_MSG";
		grep 'echo "OK' ${SCRIPT} |sed -e 's/"//g' -e 's/\t//g' -e 's/^echo //' |grep -v "^grep";
		exit 0;;
	s)	DISABLE_CHECK="1";;
	e)	ENABLE_CHECK="1";;
	c)	CHECK_TO_CHANGE=${OPTARG};;
	i)	IGNORE_DISABLED="1";;
	h|*)	func_printhelp;;
	esac
done
shift $(($OPTIND -1))

if [[ "${ENABLE_CHECK}" = "1" ]]; then
	func_enable_check; exit 0
fi

if [[ "${DISABLE_CHECK}" = "1" ]]; then
	func_disable_check; exit 0
fi

if [[ -z "${USER}" ]]; then
	USER=$(wohami)
fi

func_msg debug "USER=[${USER}]"

if [[ "${USER}" != "root" ]]; then
	func_msg ERROR "User not root."
	exit 1
fi

if [[ "${TIVOLI}" = "1" ]]; then 
	if [[ -f "${INFO_FILE}.older" ]]; then
		mv "${INFO_FILE}.older" "${INFO_FILE}.oldest"
	fi
	if [[ -f "${INFO_FILE}.old" ]]; then
		mv "${INFO_FILE}.old" "${INFO_FILE}.older"
	fi
	if [[ -f "${INFO_FILE}" ]]; then
		mv "${INFO_FILE}" "${INFO_FILE}.old"
	fi
fi

# get dist infos
func_getdistro


func_msg CHAPTER "Boot parameters"
check_bootloader #CHM0
check_init


func_msg CHAPTER "System Config"
check_mandatory_files
check_mandatory_procs
check_vgs  #CHM0
fucn_no_tivoli check_dump
check_passwd_consistancy
check_rpm_dependencies #CHM0
check_timezone #CHM0
fucn_no_tivoli check_ntp
check_system_id


func_msg CHAPTER "CPU/Memory"
fucn_no_tivoli check_paging_space
fucn_no_tivoli check_load
fucn_no_tivoli check_paging
check_hanging_io
fucn_no_tivoli check_running_procs
fucn_no_tivoli check_mem_usage
#CHM1
fucn_no_tivoli check_zombies


func_msg CHAPTER "Network"
check_default_gw
fucn_no_tivoli check_dns
fucn_no_tivoli check_ldap
fucn_no_tivoli check_nscd_sssd
check_eth


func_msg CHAPTER "Storage"
check_nfs
#check_fscsi
#CHM0
fucn_no_tivoli check_multipath_io
fucn_no_tivoli check_iscsi
#CHM2
fucn_no_tivoli check_IOwait
#CHM15
fucn_no_tivoli check_Inodes_usage


func_msg CHAPTER "General"
fucn_no_tivoli check_system_errors
fucn_no_tivoli check_frame
fucn_no_tivoli check_Appcom

fucn_no_tivoli func_summary


#CHM3

if [[ "${TIVOLI}" = "1" ]] && [[ -f "${INFO_FILE}" ]] && [[ -f "/usr/bin/mailx" ]]; then
	echo -e "There were some warnings during the ${SCRIPT_SHORTNAME} run.\nOnly messages with status error are alerted via Tivoly.\nPlease check the File: ${INFO_FILE} for more informations.\nIf the file does not exist anymore the warnings are already fixed.\n\n$(cat ${INFO_FILE})" |mailx -s "test" root
fi

if [[ "${TIVOLI}" = "1" || "${DEBUG}" = "1" ]] && [[ "${TIVOLI_ERROR}" != "1" ]]; then
	echo "OK;All checks ran without errors or warnings."
fi

echo " ";
echo -n "CSV;";
cat "$HEALTHCHECK_CSV" |sed "s/-Loc/;-Loc/g"|awk -F';' '{print $1";"$4";"$6";"$8";"$10";"$12";"$14";"$16}'

exit 0
