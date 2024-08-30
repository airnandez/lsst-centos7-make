#!/bin/bash

#-----------------------------------------------------------------------------#
# Description:                                                                #
#    use this script to build the specified version of the LSST software      #
#    framework in the context of a Docker container.                          #
#    It is designed to be used either within the context of a Docker container#
# Usage:                                                                      #
#                                                                             #
#    runContainer.sh [-v <host volume>] [-d <target directory>] [-i]          #
#                    [-B <base product>] [-Z] [-X] -t <tag>                   #
#                                                                             #
#    where:                                                                   #
#        <host volume> is the storage volume in the host where the container  #
#            is executed. That volume will be used for building and storing   #
#            a .tar.gz file of the LSST software distribution.                #
#            Default: /mnt                                                    #
#                                                                             #
#        <tag> is the tag, as known by EUPS, of the LSST software to build,   #
#            such as "v12_1" for a stable version or "w_2016_30" for a weekly #
#            version.                                                         #
#            This flag must be provided.                                      #
#                                                                             #
#        <target directory> is the absolute path of the directory under which #
#            the software will be deployed. This script creates subdirectories#
#            under <target directory> which depend on the <base product>      #
#            and the <tag>. If <tag> refers to a stable tag of "lsst_distrib" #
#            and the tag is "v14_1", the subdirectories will be               #
#               <target directory>/lsst_distrib/v14.1                         #
#            If the <tag> refers to a weekly release, say "w_2018_14", the    #
#            the subdirectories will be                                       #
#               <target directory>/lsst_distrib/w_2018_14                     #
#            If <target directory> does not already exist, this script will   #
#            create it.                                                       #
#            Default: "/cvmfs/sw.lsst.eu/<os>-<arch>" where <os> can be       #
#            "darwin" or "linux" and <arch> will typically be "x86_64"        #
#                                                                             #
#        -i  run the container in interactive mode.                           #
#                                                                             #
#        <base product> is the identifier of the base product to install.     #
#            Default: "lsst_distrib"                                          #
#                                                                             #
#        -Z  allow EUPS to use binary tarballs (if available)                 #
#                                                                             #
#        -X  mark the build directory as experimental                         #
#                                                                             #
#        -U  don't upload archive file to archive                             #
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
source 'functions.sh'

#
# Init
#
thisScript=$(basename $0)

#
# Usage
#
function usage () {
    echo "Usage: ${thisScript} [-v <host volume>] [-d <target directory>] [-i] [-B <base product>] [-Z] [-X] [-U] -t <tag>"
}

# Directory in the host exposed to the container to build the software on
hostVolume="/mnt"

# Default target directory to build the software in (in container namespace)
targetDir="/cvmfs/${cvmfsRepoName}"

# By default, run the container in detached mode
interactive=false

# Default base product to install
baseProduct="lsst_distrib"

# By default, don't use binary tarballs
useBinaries=false

# Is this a build for an experimental version?
isExperimental=false

# Should we upload the archive file?
doUpload=true

#
# Parse command line arguments
#
while getopts B:d:it:Uv:XZ optflag; do
    case $optflag in
        B)
            baseProduct=${OPTARG}
            ;;
        d)
            targetDir=$(readlink -f "${OPTARG}")
            ;;
        i)
            interactive=true
            ;;
        t)
            tag=${OPTARG}
            ;;
        U)
            doUpload=false
            ;;
        v)
            hostVolume=$(readlink -f "${OPTARG}")
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

# Check we have a product tag to build
if [[ -z "${tag}" ]]; then
    usage
    exit 0
fi

# Does the host volume actually exist?
if [[ ! -d ${hostVolume} ]]; then
    echo "${thisScript}: ${hostVolume} does not exist"
    exit 1
fi

# Path of the in-container volume: we use the first component of the target
# directory path. For instance, if the target directory is '/cvmfs/sw.lsst.eu',
# in the container we mount the volume at '/cvmfs'
containerVolume=$(echo ${targetDir} | awk '{split($0,a,"/"); printf "/%s", a[2]}')

if [ "${interactive}" == true ]; then
    runMode="--interactive --tty"
    cmd="/bin/bash"
else
    runMode="--detach  --rm"
    [[ ${useBinaries} == true ]] && binaryFlag="-Z"
    [[ ${isExperimental} == true ]] && experimentalFlag="-X"
    [[ ${doUpload} == false ]] && uploadFlag="-U"
    cmd="/bin/bash makeStack.sh -d ${targetDir} -B ${baseProduct} ${binaryFlag} ${experimentalFlag} ${uploadFlag} -t ${tag}"
fi

# Set environment variables to pass to the container
if [ -f ~/.rclone.conf ]; then
    envVars="-e RCLONE_CREDENTIALS=$(base64 -w 0 < ~/.rclone.conf)"
fi

# Run the container
imageName="airnandez/lsst-almalinux-build"
containerName=$(echo ${imageName} | cut -d '/' -f 2)
docker run \
    --name "${containerName}-${baseProduct}-${tag}"  \
    --volume "${hostVolume}:${containerVolume}"      \
    ${runMode}                                       \
    ${envVars}                                       \
    ${imageName}                                     \
    ${cmd}