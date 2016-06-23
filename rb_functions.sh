#!/bin/bash

#######################################################################
# Copyright (c) 2014 ENEO Tecnología S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License License for more details.
# You should have received a copy of the GNU Affero General Public License License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

RBDIR=${RBDIR:-/usr/lib/redborder}
RBLIB=${RBLIB:-${RBDIR}/lib}
RBETC=${RBETC:-/etc/redborder}
RBBIN=${RBBIN:-${RBDIR}/bin}
PATH=$PATH:${RBDIR}
FORCE=0
DEBUG=0

ACTUALDIR=`pwd`
INSTALL_CONF="${RBETC}/install.conf"
CAT=$(which cat 2>/dev/null)

GREEN=$'\e[32;01m'
YELLOW=$'\e[33;01m'
RED=$'\e[31;01m'
HILITE=$'\e[36;01m'
BRACKET=$'\e[34;01m'
BOLD=$'\e[1m'
NORMAL=$'\e[0m'

RBTMP="/tmp/redborder"

mkdir -p $RBTMP

PCTF="$RBTMP/rb_progress-counter-$$"
MSGF="$RBTMP/rb_progress-text-$$"
logfile="$RBTMP/rb_log-$$"
tempfile="$RBTMP/rb_tmp-$$"
resfile="$RBTMP/rb_res-$$"
DEBUGF="$RBTMP/rb_debug-$$"
FILECHECKIPTMP="$RBTMP/rb_checkip-$$"

[ -f "$PCTF" ] && rm -f "$PCTF"
[ -f "$MSGF" ] && rm -f "$MSGF"
[ -f "$logfile" ] && rm -f "$logfile"
[ -f "$tempfile" ] && rm -f "$tempfile"
[ -f "$DEBUGF" ] && rm -f "$DEBUGF"

trap "rm -f $tempfile; rm -f $PCTF; rm -f $MSGF; rm -f $resfile; rm -f $FILECHECKIPTMP" 0 2 5 15

## Dialog options ##
export DIALOGRC="${RBETC}/dialogrc"
DIALOG="$(which dialog)"

# colors
DBLK=$'\Z0'
DR=$'\Z1'
DG=$'\Z2'
DY=$'\Z3'
DBL=$'\Z4'
DM=$'\Z5'
DC=$'\Z6'
DW=$'\Z7'
DB=$'\Zb'
DREV=$'\Zr'
DU=$'\Zu'
DN=$'\Zn'

# default size
W=72
H=10
BAKTIT=" redBorder $RBVERSION.$RBRELEASE "

[ -f /etc/init.d/functions ] && . /etc/init.d/functions
[ -f ${RBETC}/install.conf ] && . ${RBETC}/install.conf

function pdate(){
    newtime=$(date '+%s')
    if [ -f /tmp/pdate.time ]; then
      lasttime=$(head -n 1 /tmp/pdate.time)
    else
      lasttime=$newtime
    fi
    printf "STEP $(date '+%s') - %5s - $* ($(date))\n" "$(($newtime - $lasttime))"
    echo -n $newtime > /tmp/pdate.time
}

function lock_prog() {
	if [ "x$1" != "x" ]; then
		LOCKFILE=`basename $1`
		LOCKFILE="/var/lock/${LOCKFILE}.lock"

		if [ -f $LOCKFILE ]; then
        		echo "$1 is already running (LOCK FILE: $LOCKFILE)"
		        exit 1
		fi

		trap "rm -f $LOCKFILE; rm -f $tempfile; rm -f $PCTF; rm -f $MSGF; killall rb_ticker &>/dev/null; tput sgr0; exit 0" 0 2 5 15
		touch $LOCKFILE
		echo $$ > $LOCKFILE
	fi	
}

function get_args_num() {
        args_count=0

        for n in "$@"; do
                args_count=$(($args_count+1))
        done

        return $args_count
}


function set_color() {
    if [ "x$BOOTUP" != "xnone" ]; then
        green="echo -en \\033[1;32m"
        red="echo -en \\033[1;31m"
        yellow="echo -en \\033[1;33m"
        orange="echo -en \\033[0;33m"
        blue="echo -en \\033[1;34m"
        black="echo -en \\033[1;30m"
        white="echo -en \\033[255m"
        cyan="echo -en \\033[0;36m"
        purple="echo -en \\033[0;35m"
        browm="echo -en \\033[0;33m"
        gray="echo -en \\033[0;37m"
        norm="echo -en \\033[1;0m"
        eval \$$1
    fi
}

function choose_yesno_file() {
	RBTXT_TOP_DIALOG="$1"
	if [ "x$2" != "x" ]; then
		diayes "${DR}[${DN} $RBTXT_TOP_DIALOG ${DR}]${DN}"  --extra-button --extra-label "NO" --textbox $2
	fi
}

function choose_progress() {
	RBTXT_TOP_DIALOG="$1"
	$DIALOG --cr-wrap --no-collapse --colors --backtitle "$BAKTIT" --title "${DR}[${DN} $RBTXT_TOP_DIALOG ${DR}]${DN}" --gauge " " 30 $W 0
	rm -f $MSGF
	rm -f $PCTF
}


function choose_yesno() {
	if [ "x$2" == "x" ]; then
		RBTXT_TOP_DIALOG="redBorder dialog"	
		RBTXT_DIALOG="\n$1"
	else
		RBTXT_TOP_DIALOG="$1"
		RBTXT_DIALOG="\n$2"
	fi
	diayes "${DR}[${DN} $RBTXT_TOP_DIALOG ${DR}]${DN}" --yesno "$RBTXT_DIALOG"
}

function choose_noyes() {
	if [ "x$2" == "x" ]; then
		RBTXT_TOP_DIALOG="redBorder dialog"	
		RBTXT_DIALOG="\n$1"
	else
		RBTXT_TOP_DIALOG="$1"
		RBTXT_DIALOG="\n$2"
	fi
	diano "${DR}[${DN} $RBTXT_TOP_DIALOG ${DR}]${DN}" --yesno "$RBTXT_DIALOG"
}

function choose_box1() {
	choose_box "$1" "" "$2" "$3"
	RBOPTION=${RBOPTION[0]}
}

function choose_box() {
	RBOPTION=()
	RBTXT_TOP_DIALOG="$1"
	RBTXT_DIALOG="$2"
	longiflist=""
	shift 2

        get_args_num "$@"
        longnumifs=$?

	heigthlit=$(($longnumifs/2))
	heigthlit=$(($heigthlit + 1))

	[ $heigthlit -gt 20 ] && heigthlit=20

	counter=0
	counter_pair=0
	for n in "$@"; do 
		counter1=$(($counter+1))
		if [ $counter_pair -eq 0 ]; then
			if [ "x$n" == "x" ]; then
				longiflist="$longiflist \"  $n\" $counter1 1"
			else
				longiflist="$longiflist \"$n:\" $counter1 1"
			fi
			counter_pair=1
		else
			longiflist="$longiflist \"$n\" $counter1 28 $W 25 "
			counter_pair=0
			counter=$(($counter+1))
		fi
	done

	if [ $FORCE -eq 0 ]; then
		TIT="${DR}[${DN} $RBTXT_TOP_DIALOG ${DR}]${DN}"
		diasim --title "\"$TIT\"" --form "\" $RBTXT_DIALOG\"" 0 0 $heigthlit $longiflist 2> "$tempfile"
		RET=$?
	else
		RET=0
		echo -n "" > "$tempfile"
		counter_pair=0
		for n in "$@"; do 
			if [ $counter_pair -eq 0 ]; then
				counter_pair=1
			else
				echo "$n" >> "$tempfile"
				counter_pair=0
			fi
		done
	fi
		
        
	if [ $RET -eq 0 ]; then
                counter=0
		while read line; do
			RBOPTION[$counter]="$line"
                        counter=$(($counter+1))
		done < "$tempfile"
	fi
}

#
# Select prompt of option
#

function choose_dialog() {
        RBOPTION=""
        RBTXT_TOP_DIALOG="$1"
        RBTXT_DIALOG="$2"
	longiflist=""
        shift 2

        get_args_num "$@"
        longnumifs=$?
        heigthlit=$(($longnumifs +10))

        [ $heigthlit -gt 20 ] && heigthlit=20

        longiflist=""
        counter=1

        for n in "$@"; do 
                longiflist="$longiflist \"$counter\" \"$n\" "

                if [ $counter -eq 1 ]; then
                        longiflist="$longiflist ON"
                else
                        longiflist="$longiflist off"
                fi

                counter=$(($counter+1))
        done

	if [ $FORCE -eq 0 ]; then
        	TIT="${DR}[${DN} $RBTXT_TOP_DIALOG ${DR}]${DN}"
	        diasim --title "\"$TIT\"" --radiolist "\"\n$RBTXT_DIALOG\"" $heigthlit $W $longnumifs $longiflist 2> $tempfile
        	RET=$?
	        choice=`cat $tempfile`
	else
		RET=0
		choice=1
	fi

        if [ "x$choice" != "x" ]; then
                counter=1
                for n in "$@"; do
                        if [ "x$counter" == "x$choice" ]; then
                                RBOPTION="$n"
                        fi
                        counter=$(($counter+1))
                done
        fi

}

function choose_dialog_text() {
    choose_if_finished=""

    RBTXT_DIALOG="$1"
    shift

    rangesize="200"
    longiflist=`echo $@ | tr '[:space:]' '\n' | sort -n | tr '\n' ' '`
    longnumifs=`echo $longiflist | wc -w | awk '{print $1}'`

    
    let "onescreen=longnumifs<rangesize"
    if [ "${onescreen}" == "1" ] ; then
        longiflist=`echo $longiflist | sort -t ' ' -n`
        while [ -z "$choose_if_finished" ] ; do
            clear
            if [ -n "$RBTXT_DIALOG" ]; then
                        echo $RBTXT_DIALOG
            else
                        echo "Choose an option:"
            fi
            echo $separator
            select n in ${longiflist} ;
            do
                        if [ -z "${n}" ] ; then
                                n=$REPLY
                        fi
                        case $n in
                                'e')
                                        RBOPTION=""
                                        choose_if_finished="yes"
                                        ;;
                                ?*)
                                        RBOPTION="$n"
                                        choose_if_finished="yes"
                                        ;;
                        esac
                        break
           done
                choose_if_finished="yes"
        done
    fi
}

function insert_user_password() {
	choose_box "redBorder Dialog" "Please enter a valid username and password" "Username" "$1" "Password" "$2"
	USER=${RBOPTION[0]}
	PASSWORD=${RBOPTION[1]}
}

#
# Insert user of device
#
function insert_user() {

        echo "$MODEL" | grep "BNT" &>/dev/null
        if [ $? -ne 0 ]; then
                USER=""

                QUESTION="$1"
                PTAGS="$2"
                UDEFAULT="$3"

                if [ "x$1" == "x" ]; then
                       QUESTION="Please enter the username"
                fi

                if [ "x$2" == "x" ]; then
                       PTAGS="Username"
                fi

                if [ "x$3" == "x" ]; then
                       UDEFAULT="rb$$"
                fi

                choose_box "redBorder Dialog" "$QUESTION" "$PTAGS" "$UDEFAULT"

                USER=${RBOPTION[0]}
                uflag=1
        fi
}

#
# Insert user of device
#
function insert_user_text() {
        echo "$MODEL" | egrep -i "BNT" &>/dev/null
        if [ $? -ne 0 ]; then
                echo -n "Please enter username: "
                read USER
                uflag=1
        fi
}


#
# Insert password of device 
#
function insert_password() {
	PASSWORD=""

	QUESTION="$1"
	PTAGS="$2"
	PDEFAULT="$3"

	if [ "x$1" == "x" ]; then
		QUESTION="Please enter the password"
	fi

	if [ "x$2" == "x" ]; then
		PTAGS="Password"
	fi

	if [ "x$3" == "x" ]; then
		PDEFAULT="rb$$"
	fi

	choose_box "redBorder Dialog" "$QUESTION" "$PTAGS" "$PDEFAULT"
	PASSWORD=${RBOPTION[0]}
}

function insert_password_text() {
	echo -n "Please enter password: "
	tput invis
	read PASSWORD
	tput sgr0
}

#
# Function wait until the arg ip is alived 
# usage:   is_alived ip [counter_limit]
# return alived_flag (0 -> dead    1-> alived)

function is_alived() {
        counter=0
        alived_flag=0

        PING_IP="$1"

	if [ "x$PING_IP" != "x" ]; then
		if [ "x$2" != "x" ]; then
			limit_counter=$2
		else
			limit_counter=300
		fi

	        while [ $counter -lt $limit_counter -a $alived_flag -eq 0 ]; do
        	        ping -c 1 $PING_IP &>/dev/null

                	if [ $? -eq 0 ]; then
	                        alived_flag=1
        	        fi

                	counter=$(($counter + 1))
	        done
	fi

}


function subnet2mask () {
	subnet="$1"
	[ "x$subnet" = "x255.255.255.255" ] && masklen=32
	[ "x$subnet" = "x255.255.255.254" ] && masklen=31
	[ "x$subnet" = "x255.255.255.252" ] && masklen=30
	[ "x$subnet" = "x255.255.255.248" ] && masklen=29
	[ "x$subnet" = "x255.255.255.240" ] && masklen=28
	[ "x$subnet" = "x255.255.255.224" ] && masklen=27
	[ "x$subnet" = "x255.255.255.192" ] && masklen=26
	[ "x$subnet" = "x255.255.255.128" ] && masklen=25
	[ "x$subnet" = "x255.255.255.0" ] && masklen=24
	[ "x$subnet" = "x255.255.254.0" ] && masklen=23
	[ "x$subnet" = "x255.255.252.0" ] && masklen=22
	[ "x$subnet" = "x255.255.248.0" ] && masklen=21
	[ "x$subnet" = "x255.255.240.0" ] && masklen=20
	[ "x$subnet" = "x255.255.224.0" ] && masklen=19
	[ "x$subnet" = "x255.255.192.0" ] && masklen=18
	[ "x$subnet" = "x255.255.128.0" ] && masklen=17
	[ "x$subnet" = "x255.255.0.0" ] && masklen=16
	[ "x$subnet" = "x255.254.0.0" ] && masklen=15
	[ "x$subnet" = "x255.252.0.0" ] && masklen=14
	[ "x$subnet" = "x255.248.0.0" ] && masklen=13
	[ "x$subnet" = "x255.240.0.0" ] && masklen=12
	[ "x$subnet" = "x255.224.0.0" ] && masklen=11
	[ "x$subnet" = "x255.192.0.0" ] && masklen=10
	[ "x$subnet" = "x255.128.0.0" ] && masklen=9
	[ "x$subnet" = "x255.0.0.0" ] && masklen=8
	[ "x$subnet" = "x254.0.0.0" ] && masklen=7
	[ "x$subnet" = "x252.0.0.0" ] && masklen=6
	[ "x$subnet" = "x248.0.0.0" ] && masklen=5
	[ "x$subnet" = "x240.0.0.0" ] && masklen=4
	[ "x$subnet" = "x224.0.0.0" ] && masklen=3
	[ "x$subnet" = "x192.0.0.0" ] && masklen=2
	[ "x$subnet" = "x128.0.0.0" ] && masklen=1
	[ "x$subnet" = "x0.0.0.0" ] && masklen=0

	return $masklen
}

function cleannetwork() {
	# remove IPs. func [dhcp]
	for m in `ip -o a s $n | grep inet | grep brd | awk '{print $4}'`; do
		ip a del $m dev $n &>/dev/null
	done
	
	if [ "x$1" == "xdhcp" ] ; then
		while [ $RET -eq 0 ]; do
			killall -9 dhclient &> /dev/null
			RET=$?
		done
	fi
}

function lines2var() {
    # Parse a file, each newline is a new var. 21 lines max
    FILE="$1"
    while read line; do
        if [ -z "$v0" ] ; then
            v0="$line"
        elif [ -z "$v1" ] ; then
            v1="$line"
        elif [ -z "$v2" ] ; then
            v2="$line"
        elif [ -z "$v3" ] ; then
            v3="$line"
        elif [ -z "$v4" ] ; then
            v4="$line"
        elif [ -z "$v5" ] ; then
            v5="$line"
        elif [ -z "$v6" ] ; then
            v6="$line"
        elif [ -z "$v7" ] ; then
            v7="$line"
        elif [ -z "$v8" ] ; then
            v8="$line"
        elif [ -z "$v9" ] ; then
            v9="$line"
        elif [ -z "$v10" ] ; then
            v10="$line"
        elif [ -z "$v11" ] ; then
            v11="$line"
        elif [ -z "$v12" ] ; then
            v12="$line"
        elif [ -z "$v13" ] ; then
            v13="$line"
        elif [ -z "$v14" ] ; then
            v14="$line"
        elif [ -z "$v15" ] ; then
            v15="$line"
        elif [ -z "$v16" ] ; then
            v16="$line"
        elif [ -z "$v17" ] ; then
            v17="$line"
        elif [ -z "$v18" ] ; then
            v18="$line"
        elif [ -z "$v19" ] ; then
            v19="$line"
        elif [ -z "$v20" ] ; then
            v20="$line"
        fi
    done < "$FILE"
}

function unl2v() {
    # Unset vars setted by lines2var
    unset v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16 v17 v18 v19 v20
}


####################################
#       Dialog functions
####################################

function diayes() {
	# general use of dialog. you can pass H & W before the function
	if [ $FORCE -eq 0 ]; then
		$DIALOG --cr-wrap --no-collapse --colors --backtitle "$BAKTIT" --title "$@" $H $W
	fi
}

function diano() {
    # general use of dialog. you can pass H & W before the function
    if [ $FORCE -eq 0 ]; then
        $DIALOG --cr-wrap --no-collapse --colors --backtitle "$BAKTIT" --defaultno --title "$@" $H $W
    fi
}

function diasim() {
    #echo $DIALOG --cr-wrap --no-collapse --colors --backtitle "\"$BAKTIT\"" "$@" 
    #echo $DIALOG --cr-wrap --no-collapse --colors --backtitle "\"$BAKTIT\"" "$@" | bash
    $DIALOG --cr-wrap --no-collapse --colors --backtitle "\"$BAKTIT\"" "$@"

    # simplified function for advanced widgets
    #$DIALOG --cr-wrap --no-collapse --colors --backtitle "\"$BAKTIT\"" "$@"
}

function diaerr() {
    # error dialog
    if [ $FORCE -eq 0 ]; then
        H=10
        W=70
        $DIALOG --cr-wrap --no-collapse --colors --backtitle "$BAKTIT" --title "${DR}[ ERROR ]${DN}" --msgbox "\n$@" $H $W $P
    fi
}

function diagmsgtab() {
	diagmsg "     -" $@
}

function diagmsg() {
	# Display message in progress bar dialog
	MSG=""
	if [ -f "$MSGF" ] ; then
		MSG=`cat $MSGF`
		if [ "x$MSG" == "x" ]; then
			MSG="
"
		fi
	else
		MSG="
"
	fi
	
	MSG="$MSG
$@"

	echo "$MSG" > $MSGF
	echo "XXX"
	echo "$MSG"
	echo "XXX"
	diagpct 0
}

function diagcmd() {

	if [ "x$@" != "x" ]; then
		diagcmd_out=`$@`
	fi

	if [ "x$diagcmd_out" != "x" ]; then
		diagmsg $diagcmd_out
	fi
}

function diagpct() {
	# Grow percent for progressbar. func num_to_grow. func 100 to full the bar
	if [ "$1" -lt 100 ] ; then
		if [ -f "$PCTF" ] ; then
			read PCT < $PCTF
		else
			PCT=0
			echo 0 > $PCTF
		fi
		if [ "$PCT" -ge 100 ] ; then
			PCT=100
		else
			PCT=$(($PCT+$1))
		fi
	else
		PCT=100
	fi

	echo $PCT
	echo $PCT > $PCTF

	[ $FORCE -eq 0 ] && sleep 1
}


function read_value_msbip() {
	# Get info IP MSB
	if [ "x$MSBIP" == "x" ]; then
		choose_box "redBorder Dialog" "Insert a valid MSB IP" "IP address" ""
	        MSBIP=$RBOPTION
	fi

        if [ "x$MSBIP" == "x" ]; then
		diaerr "You must specify a valid IP for the MSB"
		return 1
	fi

	return 0
}


function read_value_devip() {
	# Get IP Device
	if [ "x$DEVIP" == "x" ]; then
		if [ "x$LISTIP" == "x" ]; then
			choose_box "redBorder Dialog" "Insert a  valid IP for the device to update" "IP address" ""
		else
			LISTIP="$LISTIP Other"
		        choose_dialog "redBorder Dialog" "Select an ip to update" $LISTIP
		fi
	        DEVIP=$RBOPTION

		if [ "x$DEVIP" == "xOther" ]; then
			choose_box "redBorder Dialog" "Insert a  valid IP for the device to update" "IP address" ""
	        	DEVIP=$RBOPTION
		fi
	fi

	if [ "x$DEVIP" == "x" ]; then
		diaerr "You must select a valid ip to update"
		return 1
	fi

	return 0
}		

function diainfo() {
	#echo $DIALOG --cr-wrap --no-collapse --colors --backtitle "$BAKTIT" --title "${DR}[${DN} redBorder dialog ${DR}]${DN}" --msgbox "\n$@" $H $W
	if [ $FORCE -eq 0 ]; then
		$DIALOG --cr-wrap --no-collapse --colors --backtitle "$BAKTIT" --title "${DR}[${DN} redBorder dialog ${DR}]${DN}" --msgbox "\n$@" $H $W
	fi
}

function check_ip() {

	FLAG=0
	IPTOCHECK="$1"
	FRET=1

	if [ "x$IPTOCHECK" != "x" ]; then
		rm -f $FILECHECKIPTMP

		until [ $FRET -eq 0 -o $FLAG -eq 1 ]; do
			(
				diagmsg "Checking access to $IPTOCHECK ... "
				diagpct 5
				ping -c 2 $IPTOCHECK &>/dev/null
				RET=$?
				if [ $RET -eq 0 ]; then
					diagmsgtab "Connected to $IPTOCHECK"
					diagpct 45
					touch $FILECHECKIPTMP
				else
					diagmsgtab "Cannot access to the device"
					diagpct 40

					OUT=`ip r get $DEVIP 2>/dev/null | head -n 1`
					if [ "x$OUT" == "x" ]; then
						OUT="unknown"
					fi
					diagmsg "Visible: $OUT"
					diagpct 5

					diagmsg "Sleeping 5 seconds"
					sleep 5
					diagpct 25
					diagmsg "Trying again ..."
					ping -c 2 $IPTOCHECK &>/dev/null
					RET=$?
					diagpct 20

					if [ $RET -eq 0 ]; then
						diagmsgtab "Connected to $IPTOCHECK"
						touch $FILECHECKIPTMP
					else
						diagmsgtab "Still cannot access to the device"
					fi			
				fi
				diagpct 100
			) | choose_progress "Checking access"

			if [ -f $FILECHECKIPTMP ]; then
				FRET=0
			else
				# cannot access
				FRET=1
				choose_yesno "  Cannot access to $IPTOCHECK.\n  Would you like to try it again?"
				if [ $? -ne 0 ]; then
					FLAG=1
				fi
			fi
		done
	fi

	rm -f $FILECHECKIPTMP

	return $FRET
}

##############################
#    PRINTING FUNCTIONS
##############################

# function prints text on debug file if DEBUG=1
function edebug () {
	[ -n "$DEBUG" ] && echo "$@" >> $DEBUGF
}

function eerror () {
	echo -e " ${RED}*${NORMAL} $*" 2> /dev/stderr
	logger -t "rb_function.sh" "$*"
	exit 1
}

function ewarn () {
    echo -e " ${YELLOW}*${NORMAL} $*"
    logger -t "rb_function" "$*"
}

function einfo () {
    echo -e " ${GREEN}*${NORMAL} $*"
    logger -t "rb_function" "$*"
}

function einfo2() {
    echo -e "     ${GREEN}*${NORMAL} $*"
    logger -t "rb_function" "$*"
}

function elog () {
    logger -t "rb_function" "$*"
}

function etab () {
    echo -e " ${GREEN}*${NORMAL} $*"
}

function start_log() {
	echo   "Log start $@ $(date)" &> $logfile
	edebug "Log start $@ $(date)"
}


function canceled_user() {
	ERR="      Canceled by the user"
        diaerr "$ERR"
        eerror "$ERR"
}

e_ok() {
        $MOVE_TO_COL
        echo -n "["
        set_color green
        echo -n $"  OK  "
        set_color norm
        echo -n "]"
        echo -ne "\r"
        echo
        return 0
}

e_fail() {
        $MOVE_TO_COL
        echo -n "["
        set_color red
        echo -n $"FAILED"
        set_color norm
        echo -n "]"
        echo -ne "\r"
        echo
        return 1
}

function valid_ip() {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function e_title() {
    set_color cyan
    echo "######################################################################################################"
    echo -n "#  "
    set_color blue
    echo "$*"
    set_color cyan
    echo "######################################################################################################"
    set_color norm
}

function error_title() {
    set_color red
    echo "######################################################################################################"
    echo -n "#  "
    set_color orange
    echo "$*"
    set_color red
    echo "######################################################################################################"
    set_color norm
}
 
