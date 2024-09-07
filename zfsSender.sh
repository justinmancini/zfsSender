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

# Set variables and gather information

sourceDS=$1
destinationDS=$2
firstSnap=$3
snapCount=$4

if ! [[ $1 ]]; then
        echo -n "${yellow}${bold}Enter the SOURCE dataset:${reset} "
        read -r sourceDS
fi

if ! [[ $2 ]]; then
        echo -n "${yellow}${bold}Enter the DESTINATION dataset:${reset} "
        read -r destinationDS
fi

if ! [[ $3 ]]; then
        echo -n "${yellow}${bold}Enter the epoch of the FIRST snapshot you want to copy:${reset} "
        read -r firstSnap
fi

if ! [[ $4 ]]; then
        echo -n "${yellow}${bold}Enter the number of snapshots you'd like to copy after the initial snapshot:${reset} "
        read -r snapCount
fi

# Generate and print list of source napshots


if [[ $snapCount = "\*" ]]; then
	echo 1
	snapList=$( grep -o "$firstSnap.*" <(zfs list -o name -r $sourceDS -H -t snapshot -o name ) )
else
	snapList=$( grep -A"$snapCount" "$firstSnap" <(zfs list -o name -r $sourceDS -H -t snapshot -o name ) )
fi

echo -e "${yellow}${bold}Snapshot List:${reset}\n"

for snap in "$snapList"; do
	epoch=$( echo "$snap" | grep -o "@.*" | sed -e 's/@//' )
	epochList+=($epoch)
done

for X in "${epochList[@]}"; do
	echo ${cyan}$X${reset}
done

echo -en "\n${yellow}${bold}Would you like to proceed?${reset} "

read -r "yn"

while ! [[ $yn = @(y|Y|N|n) ]]; do
        echo -n "Would you like to proceed? "
        read -r "yn"
done

if ! [[ $yn = @(y|Y) ]]; then
	echo "${red}${bold}You've chosen to not proceed.  Exiting.${reset}"
	exit 0
fi

# Resume function

function resume {
	destLastSnap=$( zfs list -t snapshot -o name -r $destinationDS -H | tail -n1 | grep -o "@.*" | sed -e 's/@//' )
        destNextSnap=$( echo ${epochList[*]} | grep -o "$destLastSnap.*" | awk '{print $2}' )
	lastSnap=$( echo "${epochList[-1]}" )
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
	lastSnapCheck=$( echo ${epochList[*]} | grep -o "$destLastSnap" )
	if ! [[ $lastSnapCheck ]]; then 
		echo "${red}${bold}Destination dataset already exists, but the snapshots don't match!  Exiting.${reset}"
	else
		resume
	fi
else
	firstSnap=${epochList[0]}
	echo "${yellow}${bold}Beginning full send of ${green}$sourceDS${yellow} beginning with snapshot ${cyan}$firstSnap${yellow}..${reset}"
	snapSize=$( zfs send $sourceDS@$firstSnap -nvP | tail -n1 | awk '{print $2}' )
	snapBytes=$( numfmt --from auto $snapSize )
	zfs send $sourceDS@$firstSnap | pv --size $snapBytes | zfs recv $destinationDS
fi

lastSnap=$( echo "${epochList[-1]}" )
destLastSnap=$( zfs list -t snapshot -o name -r $destinationDS -H | grep -o "@.*" | sed -e 's/@//' )

if ! [[ $destLastSnap = $lastSnap ]]; then
	resume
fi
