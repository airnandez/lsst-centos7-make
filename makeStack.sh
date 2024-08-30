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
#                                                                             #
# Usage:                                                                      #
#    makeStack.sh [-u <user>] [-d <target directory>] [-B <base product>]     #
#                 [-x <extension>] [-Z] -t <tag>                              #
#                                                                             #
#    where:                                                                   #
#        <user> is the username which will own the software built.            #
#            Default: "lsstsw" on linux, current user on OS X                 #
#                                                                             #
#        <base product> is the identifier of the base product to install.     #
#             Default: "lsst_distrib"                                         #
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
#            <target directory>/<base product>/v12_1.                         #
#            If <target directory> does not already exist, this script will   #
#            create it.                                                       #
#            Default: "/cvmfs/sw.lsst.eu/<os>-x86_64" where <os>              #
#            is either "linux" or "darwin".                                   #
#                                                                             #
#        <extension> extension to the name of the build directory, e.g. "py2" #
#            Default: ""                                                      #
#                                                                             #
#        -Z  allow EUPS to use binary tarballs (if available)                 #
#                                                                             #
#        -X  mark the build directory as experimental                         #
#                                                                             #
# Author:                                                                     #
#    Fabio Hernandez (fabio.in2p3.fr)                                         #
#    IN2P3 / CNRS computing center                                            #
#    Lyon, France                                                             #
#                                                                             #
#-----------------------------------------------------------------------------#

#
# Import functions
#
thisScript=$(basename $0)
thisScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${thisScriptDir}/functions.sh"

#
# Init
#
user="lsstsw"
os=$(osName)
if [[ ${os} == "darwin" ]]; then
    user=${USER}
fi
targetDir="/cvmfs/${cvmfsRepoName}"
baseProduct="lsst_distrib"
useBinaries=false
isExperimental=false
doUpload=true

#
# Usage
#
function usage () {
    echo "Usage: ${thisScript} [-u <user>] [-d <target directory>] [-B <base product>] [-Z] [-X] [-U] -t <tag>"
}

#
# Parse command line arguments
#
while getopts d:t:u:B:x:UXZ optflag; do
    case $optflag in
        d)
            targetDir=$(readlink -f "${OPTARG}")
            ;;
        t)
            tag=${OPTARG}
            ;;
        u)
            user=${OPTARG}
            ;;
        B)
            baseProduct=${OPTARG}
            ;;
        U)
            doUpload=false
            ;;
        X)
            isExperimental=true
            ;;
        Z)
            useBinaries=true
            ;;
        *)
            echo "${thisScript}: unexpected option ${optflag}"
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z "${tag}" ]]; then
    usage
    exit 0
fi

#
# Is the provided tag valid?
#
if ! isValidTag ${tag}; then
    trace "'\${tag}\' is not a recognized version tag"
    exit 1
fi

#
# Retreive the name of the release directory for this release
#
releaseDir=$(getReleaseDir ${tag} ${isExperimental})

#
# Create the build directory: the build directory depends on the specified target
# directory. The build directory ends like "lsst_distrib/v13.0" or "lsst_distrib/w_2017_10".
#
targetDir="${targetDir}/$(osDistribArch)"
buildDir="${targetDir}/${baseProduct}/${releaseDir}"
if [[ -d ${buildDir} ]]; then
    # Remove build directory if it already exists: newinstall.sh doesn't install
    # in a non-empty directory
    chmod -R u+w ${buildDir}
    rm -rf ${buildDir}
fi
mkdir -p ${buildDir}

#
# Create scratch directory
#
scratchDir="${targetDir}/scratch"
mkdir -p ${scratchDir}
export TMPDIR=${scratchDir}

#
# Create archive directory
#
archiveDir="${targetDir}/archives"
mkdir -p ${archiveDir}

#
# Create log directory
#
logDir="${targetDir}/log"
mkdir -p ${logDir}
logFile=${logDir}/${baseProduct}-${releaseDir}.log
rm -f ${logFile}
touch ${logFile}

#
# Set ownership of created directories
#
chown -R ${user} ${buildDir} ${scratchDir} ${archiveDir} ${logDir}

#
# Launch installation
#
[[ ${useBinaries} == true ]] && binaryFlag="-Z"
[[ ${doUpload} == false ]] && uploadFlag="-U"

if [[ $(whoami) == ${user} ]]; then
    (./buildStack.sh -p ${baseProduct} -b ${buildDir} -a ${archiveDir} ${binaryFlag} ${uploadFlag} -t ${tag}) < /dev/null  &> ${logFile}
    rc=$?
else
    (su "${user}" -c "./buildStack.sh -p ${baseProduct} -b ${buildDir} -a ${archiveDir} ${binaryFlag} ${uploadFlag} -t ${tag}") < /dev/null &> ${logFile}
    rc=$?
fi

exit ${rc}
