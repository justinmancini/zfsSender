#!/bin/bash

# Styling
TERM=xterm-256color
red="$(tput setaf 1)"
green="$(tput setaf 2)"
yellow="$(tput setaf 3)"
magenta="$(tput setaf 5)"
cyan="$(tput setaf 6)"
bold="$(tput bold)"
reset="$(tput sgr0)"

# Help function
function help {
echo -e "\nThis script was written to aid in the sending and receiving of specific ZFS snapshots from one Zpool to another.\n"

echo -e "\nScript usage:\n"

echo -e "\n./zfsSender.sh -o [source dataset] -d [destination dataset]\n"

echo -e "\nOptions:\n"

echo -e "\n-f  -  Initial snapshot to send"
echo -e "\n-c  -  Number of snapshots to send after the initial.  (If you set this to 4, you will transfer 5 total snapshots)"
echo -e "\n-h  -  View help menu"
}

# Set variables and gather information

while getopts ':o:d:f:c:r:' opt ; do
        case $opt in
		o) sourceDS=${OPTARG} ;;
		d) destinationDS=${OPTARG} ;;
                f) firstSnap=${OPTARG} ;;
		c) snapCount=${OPTARG} ;;
		r) rangeEnd=${OPTARG} ;;

                \?) echo "${red}${bold}Invalid option -$OPTARG${reset}"; help; exit ;;
        esac
done

if ! [[ $sourceDS ]]; then
        echo -n "${yellow}${bold}Enter the SOURCE dataset:${reset} "
        read -r sourceDS
fi

if ! [[ $destinationDS ]]; then
        echo -n "${yellow}${bold}Enter the DESTINATION dataset:${reset} "
        read -r destinationDS
fi

if ! [[ $firstSnap ]]; then
        echo -n "${yellow}${bold}Initial snapshot was not specified.  Using first available snapshot - "
	firstSnap=$( zfs list -o name -H -t snapshot -r $sourceDS | head -n1 | grep -o "@.*" | sed -e 's/@//' )
	echo -e "$firstSnap"
fi

if ! [[ $snapCount ]] | [[ $rangeEnd ]]; then
        echo -e "${yellow}${bold}No end snapshot or snapshot count was entered.  Sending all snapshots after $firstSnap.${reset}"
	snapCount="all"
fi

# Ensure source dataset exists

if ! [[ $( zfs list -o name -H -r $sourceDS ) ]]; then
	echo -e "${red}${bold}Error!  The source dataset does not exist, or the zpool is not imported!"
 	exit 1
 fi
 
# Generate and print list of source napshots


if [[ $snapCount = "all" ]]; then
	fullSourceList=$( zfs list -o name -r $sourceDS -H -t snapshot -o name )
	snaps=$( echo $fullSourceList | grep -o "$sourceDS@$firstSnap.*" )
	for snap in $snaps; do
		snapList+=($snap)
	done
else
	snaps=$( grep -A"$snapCount" -o "$sourceDS@$firstSnap" <(zfs list -o name -r $sourceDS -H -t snapshot -o name ) )
	for snap in $snaps; do
		snapList+=($snap)
	done
fi

if ! [[ ${snapList[*]} ]]; then
	echo -e "${red}${bold}Error!  Unable to generate a list of snapshots!"
 	exit 1
 fi

for snap in "${snapList[@]}"; do
	snapName=$( echo "$snap" | grep -o "@.*" | sed -e 's/@//' )
	snapNameList+=($snapName)
done

echo "${cyan}${snapNameList[@]}${reset}"

echo -e "${yellow}${bold}Snapshot List:${reset}\n"

echo -en "\n${yellow}${bold}Would you like to proceed?${reset} "

read -r "yn"

while ! [[ $yn = @(y|Y|N|n) ]]; do
        echo -n "Would you like to proceed (y/n only)? "
        read -r "yn"
done

if ! [[ $yn = @(y|Y) ]]; then
	echo "${red}${bold}You've chosen to not proceed.  Exiting.${reset}"
	exit 0
fi

# Resume function

function resume {
	destLastSnap=$( zfs list -t snapshot -o name -r $destinationDS -H | tail -n1 | grep -o "@.*" | sed -e 's/@//' )
        destNextSnap=$( echo ${snapNameList[*]} | grep -o "$destLastSnap.*" | awk '{print $2}' )
	lastSnap=$( echo "${snapNameList[-1]}" )
	if ! [[ $destNextSnap ]]; then
		echo -e "\n${green}${bold}Transfer is complete.${reset}\n\n"
		${cyan}zfs list -t snapshot -o name,creation -r $destinationDS${reset}
		exit
	else
		echo "${yellow}${bold}Beginning incremental send from ${cyan}$destLastSnap${yellow} to ${cyan}$destNextSnap${yellow}..${reset}"
        	snapSize=$( zfs send -i @$destLastSnap $sourceDS@$destNextSnap -nvP | tail -n1 | awk '{print $2}' )
	        snapBytes=$( numfmt --from auto $snapSize )
		zfs send -i @$destLastSnap $sourceDS@$destNextSnap | pv --size $snapBytes | zfs recv $destinationDS
	fi
	if ! [[ $destLastSnap = $lastSnap ]]; then
        	resume
	else
		exit
	fi
}

# Check to see if destination exists

destCheck=$( zfs list $destinationDS -o name -H 2>/dev/null)

if [[ $destCheck ]]; then
	destLastSnap=$( zfs list -t snapshot -o name -r $destinationDS -H | tail -n1 | grep -o "@.*" | sed -e 's/@//' )
	lastSnapCheck=$( echo ${snapNameList[*]} | grep -o "$destLastSnap" )
	if ! [[ $lastSnapCheck ]]; then 
		echo "${red}${bold}Destination dataset already exists, but the snapshots don't match!  Exiting.${reset}"
	else
		resume
	fi
else
	firstSnap=${snapNameList[0]}
	echo "${yellow}${bold}Beginning full send of ${green}$sourceDS${yellow} beginning with snapshot ${cyan}$firstSnap${yellow}..${reset}"
	snapSize=$( zfs send $sourceDS@$firstSnap -nvP | tail -n1 | awk '{print $2}' )
	snapBytes=$( numfmt --from auto $snapSize )
	zfs send $sourceDS@$firstSnap | pv --size $snapBytes | zfs recv $destinationDS
fi

lastSnap=$( echo "${snapNameList[-1]}" )
destLastSnap=$( zfs list -t snapshot -o name -r $destinationDS -H | grep -o "@.*" | sed -e 's/@//' )

if ! [[ $destLastSnap = $lastSnap ]]; then
	resume
fi
