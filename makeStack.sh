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
#            the software will be deployed. This script creates subdirectories#
#            under <target directory> which depends on the tag.               #
#            For instance, the stack with tag "v12_1" will be installed under #
#            <target directory>/lsst_distrib/v12_1.
#            If <target directory> does not already exist, this script will   #
#            create it.                                                       #
#            Default: "/cvmfs/lsst.in2p3.fr/software/<os>-x86_64" where <os>  #
#            is either "linux" or "darwin".                                   #
#                                                                             #
#        <products> is the comma-separated list of EUPS products to be        #
#            installed in addition to "lsst_distrib".  "lsst_distrib" is      #
#            always installed first.                                          #
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
targetDir="/cvmfs/lsst.in2p3.fr/software/${os}-x86_64"
user="lsstsw"
baseProduct="lsst_distrib"

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
            targetDir=${OPTARG}
            ;;
        t)
            tag=${OPTARG}
            ;;
        u)
            user=${OPTARG}
            ;;
        p)
            optProducts=${OPTARG}
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z "${tag}" ]]; then
    usage
    exit 0
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
# Create the build directory
#
buildDir=${targetDir}/${baseProduct}/${suffix}
rm -rf ${buildDir}
mkdir -p ${buildDir}

#
# Create scratch directory
#
scratchDir=${targetDir}/"scratch"
mkdir -p ${scratchDir}
export TMPDIR=${scratchDir}

#
# Create archive directory
#
archiveDir=${targetDir}/"archives"
mkdir -p ${archiveDir}

#
# Create log directory
#
logDir=${targetDir}/"log"
mkdir -p ${logDir}
logFile=${logDir}/${baseProduct}-${tag}.log
rm -rf ${logFile}

#
# Set ownership of created directories
#
chown -R ${user} ${buildDir} ${scratchDir} ${archiveDir} ${logDir}

#
# Launch installation
#
products=${baseProduct}
if [[ ! -z "${optProducts}" ]]; then
    products=${products},${optProducts}
fi
su "${user}" -c "./buildStack.sh -l ${logFile} -p ${products} -b ${buildDir} -a ${archiveDir} -t ${tag}"

exit 0