#!/bin/bash

#-----------------------------------------------------------------------------#
# Description:                                                                #
#    use this script to build a given version of the LSST software framework. # 
#    It is designed to be used either within the context of a Docker container#
#    or otherwise.                                                            #
#    The result of the invocation of this script is a .tar.gz file with the   #
#    requested version of the LSST software framework ready to be deployed    #
#    via CernVM-FS or on a local directory.                                   #
#                                                                             #
# Usage:                                                                      #
#    buildStack.sh -p products  -b <build directory>  -a <archive directory>  #
#                  -Y <python version>  -t <tag>                              #
#                                                                             #
#    where:                                                                   #
#        <products> is the comma-separated list of EUPS products to be        #
#            installed in addition, e.g. "lsst_distrib".
#                                                                             #
#        <build directory> is the absolute path of the directory the stack    #
#            will be built into. This directory must exist and be writable.   #
#                                                                             #
#        <archive directory> is the absolute path of the directory to store   #
#            an archive file (.tar.gz) of the stack just built.               #
#                                                                             #
#        <tag> is the tag of the EUPS product to be installed.                #
#                                                                             #
#        <python version> version of the Python interpreter to be installed   #
#            valid values are "2" or "3"
#                                                                             #
# Author:                                                                     #
#    Fabio Hernandez (fabio.in2p3.fr)                                         #
#    IN2P3 / CNRS computing center                                            #
#    Lyon, France                                                             #
#                                                                             #
#-----------------------------------------------------------------------------#

#
# Init
#
thisScript=`basename $0`
thisScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
user=`whoami`
os=`uname -s | tr [:upper:] [:lower:]`
TMPDIR=${TMPDIR:-/tmp}

#
# Routines
#
trace() {
    timestamp=`date +"%Y-%m-%d %H:%M:%S"`
    echo -e $timestamp $*
}

usage () { 
    echo "Usage: ${thisScript}  -p products  -b <build directory>  -a <archive directory>  -Y <python version> -t <tag>"
}

# Start execution
trace "$0" "$*"

#
# Parse and verify command line arguments
#
while getopts p:b:a:t:Y: optflag; do
    case $optflag in
        p)
            products=${OPTARG//,/ }
            ;;
        b)
            buildDir=${OPTARG}
            ;;
        a)
            archiveDir=${OPTARG}
            ;;
        t)
            tag=${OPTARG}
            ;;
        Y)
            pythonVersion=${OPTARG}
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z "${buildDir}" || -z "${archiveDir}" || -z "${tag}" || -z "${products}" || -z "${pythonVersion}" ]]; then
    usage
    exit 0
fi

if [[ ! -d "${buildDir}" ]]; then
    echo "${thisScript}: build directory \"${buildDir}\" does not exist"
    exit 1
fi

if [[ ! -d "${archiveDir}" ]]; then
    echo "${thisScript}: archive directory \"${archiveDir}\" does not exist"
    exit 1
fi

if [[ ${UID} = 0 ]]; then
    echo "${thisScript}: cannot run as root."
    exit 1
fi

if [[ ${pythonVersion} != "2" && ${pythonVersion} != "3" ]]; then
    echo "${thisScript}: invalid Python version \"${pythonVersion}\" - expecting 2 or 3"
    exit 1
fi

#
# Is the provided tag a stable version or a weekly version?
#
if [[ ${tag} =~ ^v[0-9]+_[0-9]+.*$ ]]; then
    # Stable version tag of the form 'v12_1'
    # The suffix will be of the form 'v12.1'
    suffix=${tag//_/.}
    githubTag=$(printf ${tag} | tr "_" "." | sed "s/^v//")
elif [[ ${tag} =~ ^w_[0-9]{4}_[0-9]{1,2}$ ]]; then
    # Weekly version tag of one of the forms 'w_2017_3' or 'w_2016_15'
    # The suffix will be identical to the weekly tag
    # The github tag has the form: w.2017.5
    suffix=${tag}
    githubTag=$(printf ${tag} | tr "_" ".")
else
    echo "${thisScript}: '${tag}' is not a recognized version tag"
    exit 1
fi

#
# Set the environment for building this release
#
[[ -f ${HOME}/enableDevtoolset.sh ]] && source ${HOME}/enableDevtoolset.sh

#
# Download the bootstrap installer from the canonical repository
#
url="https://raw.githubusercontent.com/lsst/lsst/master/scripts/newinstall.sh"
status=`curl -s --head  ${url} | head -n 1`
if [[ ${status} != HTTP*200* ]]; then
    echo "${thisScript}: download installer could not be found at ${url}"
    exit 1
fi
cd ${buildDir}
cmd="curl -s -L -o newinstall.sh ${url}"
trace "working directory" `pwd`
trace $cmd ; $cmd

#
# Set deployment target for OS X
#    10.9   Mavericks
#    10.10  Yosemite
#    10.11  El Capitan
#    10.12  Sierra
#
if [[ ${os} == "darwin" ]]; then
    export MACOSX_DEPLOYMENT_TARGET="10.9"
fi

#
# Bootstrap the installation. After executing the bootstrap script, there must
# be a file 'loadLSST.bash'
#
export TMPDIR=`mktemp -d $TMPDIR/${suffix}-build-XXXXXXXXXX`
cmd="bash newinstall.sh -P /usr/bin/python -${pythonVersion} -b -t"
trace $cmd ; $cmd
if [[ ! -f "loadLSST.bash" ]]; then
    echo "${thisScript}: file 'loadLSST.bash' not found"
    exit 1
fi

#
# Source minimal LSST environment
#
source loadLSST.bash

#
# Install conda packages not included in distribution
# The extra packages to install are specified in a text file to be consumed
# by the 'conda install' command. Each line of this file contains the name
# of a package. When installing those extra packages we make sure to not
# modify dependencies which are the conda packages on top of which the
# version of the LSST software has been tested against.
#
condaExtensionsFile="${thisScriptDir}/condaExtraPackages.txt"
if [ -f ${condaExtensionsFile} ]; then
    # Filter out comments and check if there are actually packages to install
    grep -v '^\s*#' ${condaExtensionsFile} > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        trace "installing conda extra packages"
        cmd="conda install --no-update-deps -c defaults -c astropy -c conda-forge --quiet --yes --file=${condaExtensionsFile}"
        trace $cmd ; $cmd
        if [ $? != 0 ]; then
            echo "${thisScript}: could not install conda extensions"
            exit 1
        fi
    fi
fi

#
# Download and build the requested products
#
for p in ${products}; do
    cmd="eups distrib install -t ${tag} ${p}"
    trace $cmd ; $cmd
    if [ $? != 0 ]; then
        echo "${thisScript}: command ${cmd} failed"
        exit 1
    fi
done

#
# Perform OS-specific post-installation
#
if [[ ${os} == "darwin" ]]; then
	#
	# Update the Python interpreter path of EUPS installed products
	#
    curl -sSL https://raw.githubusercontent.com/lsst/shebangtron/master/shebangtron | python
elif [[ ${os} == "linux" ]]; then
	#
	# Extend the loadLSST.*sh scripts to enable devtoolset
	#
	if [[ -f ${HOME}/enableDevtoolset.sh ]]; then
	    for s in loadLSST.*sh; do
	        grep -v "#" ${HOME}/enableDevtoolset.sh >> $s
	    done
	fi
fi

#
# Add README file for this version
#
trace "creating README"
if [[ ${os} == "linux" ]]; then
    platform=`lsb_release -d | cut -f 2-`
else
    osxName=`sw_vers -productName`
    osxVersion=`sw_vers -productVersion`
    platform="${osxName} ${osxVersion}"
fi

cat > ${buildDir}/README <<-EOF
LSST Software ${suffix}
-----------------------

Build time:     `date -u +"%Y-%m-%d %H:%M:%S UTC"`
Build platform: ${platform} `uname -s -r -v -m  -p`
Documentation:  https://github.com/airnandez/lsst-cvmfs
EOF

#
# Configure EUPS site startup file
#
trace "configuring EUPS site startup file"
cat >> ${buildDir}/stack/current/site/startup.py <<-EOF
# Configure EUPS not to try to acquire locks on a read-only file system
hooks.config.site.lockDirectoryBase = None
EOF

#
# Change permissions for this installation
#
trace "modyfying permissions under ${buildDir}"
cmd="chmod -R u-w,g-w,o-w ${buildDir}"
trace $cmd ; $cmd

#
# Make archive file
#
trace "building archive file"
tarCmd="tar"
if [[ ${os} == "darwin" ]]; then
    tarCmd="gnutar"
fi
tarFileName=`echo ${buildDir}-py${pythonVersion}-${os}"-x86_64.tar.gz" | cut -b 2- | tr [/] [_]`
archiveFile=${archiveDir}/${tarFileName}
cd ${buildDir}/..
cmd="${tarCmd} --hard-dereference -zcf ${archiveFile} ./`basename ${buildDir}`"
trace $cmd ; $cmd

#
# Upload archive file
#
uploadExe="${thisScriptDir}/upload.sh"
if [[ -x "${uploadExe}" ]]; then
    trace "uploading archive file..."
    cmd="${uploadExe} ${archiveFile}"
    trace $cmd; $cmd
else
    trace "file ${uploadExe} not executable or not found"
fi

#
# Display end message
#
trace "build process ended successfully"

#
# Clean up
#
rm -rf ${TMPDIR}
exit 0