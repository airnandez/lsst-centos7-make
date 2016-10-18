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
#    makeStack.sh [-u <user>]  [-d <target directory>]  [-p products]         #
#                  -t <tag>                                                   #
#                                                                             #
#    where:                                                                   #
#        <user> is the username which will own the software built.            #
#            Default: "lsstsw"                                                #
#                                                                             #
#        <tag> is the tag, as known by EUPS, of the LSST software to build,   #
#            such as "v12_1" for a stable version or "w_2016_30" for a weekly #
#            version.                                                         #
#            This flag must be provided.                                      #
#                                                                             #
#        <target directory> is the absolute path of the directory under which #
#            the software will be deployed. This script creates a subdirectory#
#            under <target directory> which depends on the <tag>. If <tag>    #
#            refers to a stable tag, for instance "v12_1", the subdirectory   #
#            is named "lsst-v12.1". If <tag> refers to a weekly tag, for      #
#            instance "w_2016_30", the subdirectory will be named             #
#            "lsst-w_2016_30".                                                #
#            If <target directory> does not already exist, this script will   #
#            create it.                                                       #
#            Default: "/cvmfs/lsst.in2p3.fr/software/<os>-x86_64" where <os>  #
#            is either "linux" or "darwin".                                   #
#                                                                             #
#        <products> is the comma-separated list of EUPS products to be        #
#            installed in addition to "lsst_apps".  "lsst_apps" is always     #
#            installed first.                                                 #
#            Default: ""                                                      #
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
os=`uname -s | tr [:upper:] [:lower:]`
topDir="/cvmfs/lsst.in2p3.fr/software/${os}-x86_64"
user="lsstsw"
products="lsst_apps"

#
# usage()
#
usage () { 
    echo "Usage: ${thisScript} [-u <user>] [-d <target directory>] [-p <products>] -t <tag>"
} 

#
# Parse command line arguments
#
while getopts d:t:u:p: optflag; do
    case $optflag in
        d)
            topDir=$OPTARG
            ;;
        t)
            tag=$OPTARG
            ;;
        u)
            user=$OPTARG
            ;;
        p)
            optProducts=${OPTARG//,/ }
            ;;
    esac
done
shift $((OPTIND - 1))

if [ -z "${tag}" ]; then
    usage
    exit 0
fi

#
# Is the provided tag a stable version or a weekly version?
#
if [[ ${tag} =~ v[0-9]+_[0-9]+.* ]]; then
    # Stable version tag of the form 'v12_1'
    # The suffix will be of the form 'v12.1'
    suffix=${tag//_/.}
elif [[ ${tag} =~ w_[0-9]{4}_[0-9]{2} ]]; then
    # Weekly version tag of the form 'w_2016_15'
    # The suffix will be identical to the weekly tag
    suffix=${tag}
else
    echo "${thisScript}: '${tag}' is not a recognized version tag"
    exit 1
fi

#
# Prepare the install directory and download the bootstrap installer from
# the canonical repository
#
url="https://raw.githubusercontent.com/lsst/lsst/master/scripts/newinstall.sh"
status=`curl -s --head  ${url} | head -n 1`
if [[ ${status} != HTTP*200* ]]; then
    echo "${thisScript}: download installer could not be found at ${url}"
    exit 1
fi
buildDir=${topDir}/"lsst-"${suffix}
rm -rf ${buildDir}
mkdir -p ${buildDir}
cd ${buildDir}
curl -s -L -o newinstall.sh ${url}

#
# Bootstrap the installation. After executing the bootstrap script, there must
# be a file 'loadLSST.bash'
#
scratchDir=${topDir}/scratch
mkdir -p ${scratchDir}
export TMPDIR=`mktemp -d --tmpdir=${scratchDir} lsst-${suffix}-build-XXXXXXXXXX`
log="${scratchDir}/lsst-${suffix}-install.log"
PYTHON="/usr/bin/python" bash newinstall.sh -b > ${log} 2>&1
if [ ! -f "loadLSST.bash" ]; then
    echo "${thisScript}: file 'loadLSST.bash' not found"
    exit 1
fi

#
# Download and build the requested products
#
source loadLSST.bash
for p in ${products} ${optProducts}; do
    eups distrib install -t ${tag} ${p}  >>  ${log} 2>&1
    if [ $? != 0 ]; then
        echo "${thisScript}: eups distrib install -t ${tag} ${p} failed"
        exit 1
    fi
done


#
# Add README file for this version
#
cat > ${buildDir}/README <<-EOF
LSST Software ${suffix}
-----------------------

Build time:     `date -u +"%Y-%m-%d %H:%M:%S UTC"`
Build platform: `uname -s -r -v -m  -p`
Documentation:   https://github.com/airnandez/lsst-cvmfs
EOF

#
# Configure EUPS site startup file
#
cat >> ${buildDir}/site/startup.py <<-EOF
# Configure EUPS not to try to acquire locks on a read-only file system
hooks.config.site.lockDirectoryBase = None
EOF

#
# Set ownership of the files to the specified user
#
chown -R ${user}:${user} ${buildDir}

#
# Build tar file
#
archiveDir=${topDir}/archives
mkdir -p ${archiveDir}
cd ${buildDir}/..
tar --hard-dereference \
    -zcf ${archiveDir}/lsst-${suffix}-${os}-x86_64.tar.gz ./`basename ${buildDir}`

#
# Clean up
#
rm -rf ${TMPDIR}
exit 0