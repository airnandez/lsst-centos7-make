#!/bin/bash

# Returns the description of the linux distribution, e.g. 
#    "CentOS Linux release 7.3.1611 (Core)"
#    "Ubuntu 14.04.5 LTS"
linuxDescription() {
	local description="unknown"
	# Try first the lsb_release command. It returns:
	#    Description:	Ubuntu 14.04.5 LTS
	#    Description:	CentOS Linux release 7.4.1708 (Core) 
	rel=$(command -v lsb_release)
	if [[ $rel != "" ]]; then
		description=`$rel -d | cut -f 2-`
	elif [[ -f /etc/redhat-release ]]; then
		description=`head -1 /etc/redhat-release`
	fi
	echo $description
}

# Returns the linux distribution, e.g. "CentOS", "Ubuntu"
linuxDistribution() {
	local distrib="unknown"
	# Try first the lsb_release command. It returns:
	#    Distribution:	Ubuntu 14.04.5 LTS
	#    Distribution:	CentOS Linux release 7.4.1708 (Core) 
	rel=$(command -v lsb_release)
	if [[ $rel != "" ]]; then
		distrib=`$rel -d | awk '{print $2}'`
	elif [[ -f /etc/redhat-release ]]; then
		distrib=`head -1 /etc/redhat-release | awk '{print $1}'`
	fi
	echo $distrib
}

# Returns the operating system, e.g. "linux", "darwin"
osName() {
	echo `uname -s | tr [:upper:] [:lower:]`
}

# Returns the execution platform, e.g. linux-x86_64, darwin-x86_64
platform() {
	# Get the UNIX flavor, e.g. "linux", "darwin"
	local os=$(osName)
	# Get the kernel architecture, e.g. "x86_64"
	local arch=`uname -m | tr [:upper:] [:lower:]`
	echo ${os}-${arch}
}

# Returns the description of the Python interpreter, e.g. "Python 3.6.2 :: Continuum Analytics, Inc."
pythonDescription() {
	echo `python --version 2>&1`
}

# Returns the description of the C++ compiler, e.g. "c++ (GCC) 6.3.1 20170216 (Red Hat 6.3.1-3)"
cppDescription() {
	local description=`c++ --version | head -1`
	if [[ ${MACOSX_DEPLOYMENT_TARGET} != "" ]]; then
		description="${description} [MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET}"]"
	fi
	echo ${description}
}

# Returns a description of the operating system
# e.g. "CentOS Linux release 7.3.1611 (Core)  Linux 3.10.0-514.10.2.el7.x86_64 #1 SMP Fri Mar 3 00:04:05 UTC 2017 x86_64 x86_64"
#      "Mac OS X 10.11.6 Darwin 15.6.0 Darwin Kernel Version 15.6.0: Tue Jan 30 11:45:51 PST 2018; root:xnu-3248.73.8~1/RELEASE_X86_64 x86_64 i386"
osDescription() {
	local description=""
	case $(osName) in
		"darwin")
    		description="\"`sw_vers -productName` `sw_vers -productVersion`\""
			;;

		"linux")
			description=$(linuxDescription)
			;;

		*)
			;;
	esac
	echo ${description} `uname -s -r -v -m  -p`
}

# Returns a timestamp of the form 2018-01-02 13:14:15"
trace() {
    timestamp=`date +"%Y-%m-%d %H:%M:%S"`
    echo -e $timestamp $*
}
