#!/bin/bash

#-----------------------------------------------------------------------------#
# Description:                                                                #
#    use this script to deploy a release of a LSST product on a CernVM-FS     #
#    server.                                                                  #
#    It must be executed on a stratum 0 CernVM-FS server.                     #
# Usage:                                                                      #
#                                                                             #
#    deploy.sh [-B <base product>] [-d <deploy dir>] [-a <architecture>]      #
#               -S <distribution>  -t <tag>                                   #
#                                                                             #
#    where:                                                                   #
#        <base product> is the identifier of the base product to deploy,      #
#           such as "lsst_distrib" or "lsst_sims".                            #
#           Default: "lsst_distrib"                                           #
#                                                                             #
#        <deploy dir> is the top deploy directory.                            #
#           Default: "/cvmfs/sw.lsst.eu"                                      #
#                                                                             #
#        <architecture> is the kernel architecture of the release to deploy   #
#            e.g. "x86_64", "aarch64" or "arm64"                              #
#            Default: "x86_64"                                                #
#                                                                             #
#        <distribution> is the operating system distribution to deploy this   #
#            release on.                                                      #
#            Accepted values are "darwin", "linux", "almalinux"               #
#                                                                             #
#        <tag> is the tag of the base product to be deployed. Accepted        #
#            values are of the form "w_2018_24", "v_16_0", "sims_2_8_0"       #
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
# usage()
#
usage () {
    echo "Usage: ${thisScript} [-B <base product>] [-d <deploy dir>] [-a <architecture>] [-X] -S <distribution>  -t <tag>"
}

#
# Start execution
#
trace "starting execution"
trace "$*"

# Default base product to install
baseProduct="lsst_distrib"

# Default directory to deploy the software
deployDir="/cvmfs/${cvmfsRepoName}"

# Default architecture
arch="x86_64"

# Experimental version?
isExperimental=false

#
# Parse command line arguments
#
while getopts a:B:d:S:t:X optflag; do
    case $optflag in
        a)
            arch=$(echo ${OPTARG} | tr '[:upper:]' '[:lower:]')
            ;;
        B)
            baseProduct=${OPTARG}
            ;;
        d)
            deployDir=${OPTARG}
            ;;
        S)
            distribution=$(echo ${OPTARG} | tr '[:upper:]' '[:lower:]')
            ;;
        X)
            isExperimental=true
            ;;
        t)
            tag=${OPTARG}
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z "${tag}" || -z "${distribution}" ]]; then
    usage
    exit 0
fi

#
# Validate distribution
#
case ${distribution} in
    "almalinux"|"darwin"|"linux")
        ;;

    *)
        perror "unsupported distribution \"${distribution}\" (expecting \"almalinux\", \"darwin\" or \"linux\")"
        exit 1
        ;;
esac

#
# Validate architecture
#
case ${arch} in
    "aarch64"|"arm64"|"x86_64")
        ;;
    *)
        perror "unsupported architecture \"${arch}\" (expecting \"aarch64\", \"arm64\" or \"x86_64\")"
        exit 1
        ;;
esac
distributionArch="${distribution}-${arch}"  # e.g. "almalinux-x86_64" or "darwin-arm64"

#
# Validate tag
#
if ! $(isValidTag ${tag}); then
    perror "tag \"${tag}\" is not valid"
    exit 1
fi

#
# Validate deploy directory
#
if [[ ! -d ${deployDir} ]]; then
    perror "deploy directory \"${deployDir}\" does not exist"
    exit 1
fi

#
# Ensure we are not redeploying
#
releaseDir=$(getReleaseDir ${tag} ${isExperimental})
targetDir=${deployDir}/${distributionArch}/${baseProduct}/${releaseDir}
if [[ -d ${targetDir} ]]; then
    perror "directory \"${targetDir}\" already exists. Remove it before deploying"
    exit 1
fi

#
# Prepare download directory and download the archive for the specified distribution, architecture and tag
#
archiveName="${deployDir}/${distributionArch}/${baseProduct}/${releaseDir}.tar.gz"
workDir='/cvmfs/tmp'
downloadDir="${workDir}/download"
if ! mkdir -p ${downloadDir}; then
    perror "could not create directory ${downloadDir}"
    exit 1
fi

localArchiveFilePath="${downloadDir}/$(basename ${archiveName})"
rm -f ${localArchiveFilePath}
trace "downloading archive file ${bucket}${archiveName}"
cmd="rclone copy ${bucket}${archiveName} ${downloadDir}"
trace ${cmd}
if ! ${cmd}; then
    perror "error downloading archive file"
    exit 1
fi
if [[ ! -f ${localArchiveFilePath} ]]; then
    perror "could not find downloaded archive file ${localArchiveFilePath}"
    exit 1
fi

#
# Untar archive file into a temporary directory
#
untarDir="${workDir}/${distributionArch}"
if ! mkdir -p ${untarDir}; then
    perror "could not create directory ${untarDir}"
    exit 1
fi

releaseDir="${untarDir}/${releaseDir}"
sudo rm -rf ${releaseDir}
cmd="tar --warning=no-timestamp --directory ${untarDir} -z --extract --file ${localArchiveFilePath}"
trace "untaring downloaded archive file ${localArchiveFilePath}"
trace ${cmd}
if ! ${cmd}; then
    perror "error untaring file ${localArchiveFilePath}"
    exit 1
fi

if [[ ! -d ${releaseDir} ]]; then
    perror "could not find directory ${releaseDir}"
    exit 1
fi

#
# Start cvmfs transaction
#
cmd="sudo cvmfs_server transaction ${cvmfsRepoName}"
trace ${cmd}
if ! ${cmd}; then
    perror "could not start cvmfs_server transaction"
    exit 1
fi

#
# Copy this release to its final destination directory
#
baseProductDir=$(dirname ${targetDir})
if [[ ! -d ${baseProductDir} ]]; then
    cmd="sudo mkdir -p ${baseProductDir}"
    trace ${cmd}
    if ! ${cmd}; then
        perror "could not create base product directory ${baseProductDir}, aborting..."
        cmd="sudo cvmfs_server abort -f ${cvmfsRepoName}"
        trace ${cmd}; ${cmd}
        exit 1
    fi
fi

cmd="sudo cp -pR ${releaseDir} ${baseProductDir}"
trace ${cmd}
if ! ${cmd}; then
    perror "could not copy release directory ${releaseDir} to its destination directory ${baseProductDir}, aborting..."
    cmd="sudo cvmfs_server abort -f ${cvmfsRepoName}"
    trace ${cmd}; ${cmd}
    exit 1
fi

#
# Change file ownership
#
fileOwner="lsstsw"
if getent passwd ${fileOwner} > /dev/null 2>&1; then
    cmd="sudo chown ${fileOwner}:${fileOwner} ${baseProductDir}"
    trace ${cmd}; ${cmd}
    cmd="sudo chown -R ${fileOwner}:${fileOwner} ${targetDir}"
    trace ${cmd}; ${cmd}
fi

#
# Commit this cvmfs transaction and publish the modifications
#
cmd="sudo cvmfs_server publish ${cvmfsRepoName}"
trace ${cmd}
if ! ${cmd}; then
    perror "could not commit transaction, aborting..."
    cmd="sudo cvmfs_server abort -f ${cvmfsRepoName}"
    trace ${cmd}; ${cmd}
    exit 1
fi

#
# Clean up
#
trace "cleaning up"
cmd="sudo rm -rf ${untarDir} ${downloadDir}"
trace ${cmd}; ${cmd}

trace "deployment of release ${targetDir} ended successfully"
exit 0
