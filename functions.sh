#!/bin/bash


linuxDistrib() {
	local distrib="unknown"
	# Try first the lsb_release command. It returns:
	#    Description:	Ubuntu 14.04.5 LTS
	#    Description:	CentOS Linux release 7.4.1708 (Core) 
	rel=$(command -v lsb_release)
	if [[ $rel != "" ]]; then
		distrib=`$rel -d |  awk '{print $2}'`
	elif [[ -f /etc/redhat-release ]]; then
		distrib=`head -1 /etc/redhat-release | awk '{print $1}'`
	fi
	echo $distrib
}

osName() {
	local os=`uname -s | tr [:upper:] [:lower:]`
	case $os in
		"linux")
			echo $(linuxDistrib)
			;;
		
		"darwin")
			echo "macOS"
			;;

		*)
			echo "unknown"
			;;
	esac
}
