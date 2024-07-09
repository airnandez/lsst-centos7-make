#!/bin/bash

#-----------------------------------------------------------------------------#
# Description:                                                                #
#    use this script to build the specified version of the LSST software      #
#    framework in the context of a Docker container.                          # 
#    It is designed to be used either within the context of a Docker container#
# Usage:                                                                      #
#                                                                             #
#    runContainer.sh [-v <host volume>]  [-d <target directory>]  [-i]        #
#                    [-B <base product>] [-p products] [-Z] [-X] -t <tag>     #
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
#        <base product> is the identifier of the base product to install,     #
#            such as "lsst_distrib" or "lsst_sims".                           #
#             Default: "lsst_distrib"                                         #
#                                                                             #
#        <products> is the comma-separated list of EUPS products to be        #
#            installed in addition to the base product, which is always       #
#            installed first.                                                 #
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
source 'functions.sh'

#
# usage()
#
usage () { 
    echo "Usage: ${thisScript} [-v <host volume>] [-d <target directory>] [-i] [-B <base product>] [-p <products>] [-x <extension>] [-Z] [-X] -t <tag>"
} 

#
# Init
#
thisScript=$(basename $0)

# Directory in the host to be used by the container to build the software on
hostVolume="/mnt"
mkdir -p ${hostVolume}

# Default target directory to build the software in (in container namespace)
targetDir="/cvmfs/sw.lsst.eu/$(platform)"

# By default, run the container in detached mode
interactive=false

# Default base product to install
baseProduct="lsst_distrib"

# By default, don't use binary tarballs
useBinaries=false

# Is this a build for an experimental version?
isExperimental=false

#
# Parse command line arguments
#
while getopts d:t:v:ip:B:ZX optflag; do
    case $optflag in
        d)
            targetDir=${OPTARG}
            ;;
        t)
            tag=${OPTARG}
            ;;
        v)
            hostVolume=${OPTARG}
            ;;
        i)  
            interactive=true
            ;;
        B)
            baseProduct=${OPTARG}
            ;;
        p)
            optProducts=${OPTARG}
            ;;
        Z)
            useBinaries=true
            ;;
        X)
            isExperimental=true
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z "${tag}" ]]; then
    usage
    exit 0
fi

# Path of the in-container volume: we use the first component of the target
# directory path. For instance, if the target directory is '/cvmfs/sw.lsst.eu',
# in the container we mount the volume at '/cvmfs'
containerVolume=$(echo ${targetDir} | awk '{split($0,a,"/"); printf "/%s", a[2]}')

# Does the host volume actually exist?
mkdir -p ${hostVolume} > /dev/null 2>&1
df ${hostVolume} > /dev/null 2>&1
if [ $? != 0 ]; then
    echo "${thisScript}: ${hostVolume} does not exist"
    exit 1
fi

if [ "${interactive}" == true ]; then
    mode="-it"
    cmd="/bin/bash"
else
    productsFlag=${optProducts:+"-p ${optProducts}"}
    mode="-d  --rm"
    [[ ${useBinaries} == true ]] && binaryFlag="-Z"
    [[ ${isExperimental} == true ]] && experimentalFlag="-X"
    cmd="/bin/bash makeStack.sh -d ${targetDir} -B ${baseProduct} ${productsFlag} ${binaryFlag} ${experimentalFlag} -t ${tag}"
fi

# Set environment variables for the container
envVars=""
if [ -f ~/.rclone.conf ]; then
    RCLONE_CREDENTIALS=$(cat ~/.rclone.conf | base64 -w 0)
    envVars="-e RCLONE_CREDENTIALS=${RCLONE_CREDENTIALS}"
fi

# Run the container
imageName="airnandez/lsst-almalinux-build"
containerName=$(echo ${imageName} | cut -d '/' -f 2)
docker run \
    --name ${containerName}-${baseProduct}-${tag}  \
    --volume ${hostVolume}:${containerVolume}      \
    ${mode}                                        \
    ${envVars}                                     \
    ${imageName}                                   \
    ${cmd}