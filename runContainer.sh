#!/bin/bash

#-----------------------------------------------------------------------------#
# Description:                                                                #
#    use this script to build the specified version of the LSST software      #
#    framework in the context of a Docker container.                          # 
#    It is designed to be used either within the context of a Docker container#
# Usage:                                                                      #
#    runContainer.sh [-v <host volume>]  [-d <target directory>]  [-i]        #
#                    [-p products] -t <tag>                                   #
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
#        -i  run the container in interactive mode.                           #
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
# usage()
#
usage () { 
    echo "Usage: ${thisScript} [-v <host volume>] [-d <target directory>] [-i] [-p <products>] -t <tag>"
} 

#
# Init
#
thisScript=`basename $0`

# Directory in the host to be used by the container to build the software on
hostVolume="/mnt"
mkdir -p ${hostVolume}

# Target directory to build the software in (in container namespace)
os=`uname -s | tr [:upper:] [:lower:]`
targetDir="/cvmfs/lsst.in2p3.fr/software/${os}-x86_64"

# By default, run the container in detached mode
interactive=false

#
# Parse command line arguments
#
while getopts d:t:v:ip: optflag; do
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

# Path of the in-container volume: we use the first component of the target
# directory path. For instance, if the target directory is '/cvmfs/lsst.in2p3.fr',
# in the container we mount the volume at '/cvmfs'
containerVolume=`echo ${targetDir} | awk '{split($0,a,"/"); printf "/%s", a[2]}'`

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
    mode="-d"
    cmd="/bin/bash makeStack.sh -d ${targetDir} ${productsFlag} -t ${tag}"
fi  

# Run the container
imageName="airnandez/lsst-centos7-make"
containerName=`echo ${imageName} | awk '{split($0,a,"/"); printf "%s", a[2]}'`
docker run --name ${containerName}-${tag}              \
           --volume ${hostVolume}:${containerVolume}   \
           ${mode}                                     \
           ${imageName}                                \
           ${cmd}