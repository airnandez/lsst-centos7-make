#!/bin/bash

#-----------------------------------------------------------------------------#
# Description:                                                                #
#    use this script to deploy a release of a LSST product on a CernVM-FS     #
#    server.                                                                  # 
#    It must be executed on a stratum 0 CernVM-FS server.                     #
# Usage:                                                                      #
#                                                                             #
#    deploy.sh [-B <base product>] [-d <deploy dir>] [-a <architecture>]      #
#               -S <platform>  -t <tag>                                       #
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
#            e.g. "x86_64" or "arm64"                                         #
#            Default: "x86_64"                                                #
#                                                                             #
#        <platform> is the operating system to deploy this release on         #
#            Accepted values are "darwin" or "linux"                          #
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
source 'functions.sh'

#
# usage()
#
usage () { 
    echo "Usage: ${thisScript} [-B <base product>] [-d <deploy dir>] [-a <architecture>] [-X] -S <platform>  -t <tag>"
} 

#
# Init
#
thisScript=`basename $0`

# Default base product to install
baseProduct="lsst_distrib"

# cvmfs repository name
cvmfsRepoName="sw.lsst.eu"

# Default directory to deploy the software
deployDir="/cvmfs/${cvmfsRepoName}"

# Default kernel architecture
arch="x86_64"

# Experimental version?
isExperimental=false
experimentalExt="dev"

#
# Parse command line arguments
#
while getopts B:d:a:S:t:X optflag; do
    case $optflag in
        B)
            baseProduct=${OPTARG}
            ;;
        d)
            deployDir=${OPTARG}
            ;;
        S)
            platform=${OPTARG}
            ;;
        a)
            arch=${OPTARG}
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

if [[ -z "${tag}" || -z "${platform}" ]]; then
    usage
    exit 0
fi

platform=$(echo ${platform} | tr [:upper:] [:lower:])
case ${platform} in
    "linux"|"darwin")
        ;;

    *)
        echo "${thisScript}: unsupported platform value \"${platform}\" (expecting \"linux\" or \"darwin\")"
        exit 1
        ;;
esac

arch=$(echo ${arch} | tr [:upper:] [:lower:])
case ${arch} in
    "x86_64"|"arm64")
        ;;
    *)
        echo "${thisScript}: unsupported architecture value \"${arch}\" (expecting \"x86_64\" or \"arm64\")"
        exit 1
        ;;
esac
platform=${platform}-${arch}

if [[ ! -d ${deployDir} ]]; then
    echo "${thisScript}: directory \"${deployDir}\" does not exist"
    exit 1
fi

if ! $(isValidTag ${tag}); then
    echo "${thisScript}: tag \"${tag}\" is not valid"
    exit 1    
fi

# Ensure we are not redeploying
if [[ ${tag} =~ ^v ]]; then
    bucket="rubin:stables/py3"
    tag=${tag//_/.}
elif [[ ${tag} =~ ^w ]]; then
    bucket="rubin:weeklies/py3"
elif [[ ${tag} =~ ^d ]]; then
    bucket="rubin:dailies/py3"
elif [[ ${tag} =~ ^sims_ ]]; then
    bucket="rubin:weeklies/py3"
fi
targetDir=${deployDir}/${platform}/${baseProduct}/${tag}
[[ ${isExperimental} == true ]] && targetDir="${targetDir}-${experimentalExt}"
if [[ -d ${targetDir} ]]; then
    echo "${thisScript}: directory \"${targetDir}\" already exists. Remove it before deploying"
    exit 1
fi

# Prepare download directory and download the archive for the specified tag and platform
archiveName="${deployDir}/${platform}/${baseProduct}/${tag}-py3-${platform}.tar.gz"
if [[ ${isExperimental} == true ]]; then
   archiveName="${deployDir}/${platform}/${baseProduct}/${tag}-${experimentalExt}-py3-${platform}.tar.gz"
fi
archiveName=$(echo ${archiveName} | cut -b 2- | sed -e 's|/|__|g')
workDir='/cvmfs/tmp'
downloadDir=${workDir}/download
mkdir -p ${downloadDir}
localArchiveFilePath=${downloadDir}/${archiveName}
rm -f ${localArchiveFilePath}
trace "downloading archive file ${bucket}/${archiveName}"
cmd="rclone copy ${bucket}/${archiveName} ${downloadDir}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
    echo "${thisScript}: error downloading archive file"
    exit 1
fi
if [[ ! -f ${localArchiveFilePath} ]]; then
    echo "${thisScript}: could not find downloaded archive file ${localArchiveFilePath}"
    exit 1  
fi

# Untar archive file into a temporary directory
untarDir=${workDir}/${platform}
mkdir -p ${untarDir}
releaseDir=${untarDir}/${tag}
[[ ${isExperimental} == true ]] && releaseDir="${releaseDir}-${experimentalExt}"
sudo rm -rf ${releaseDir}
cmd="tar --warning=no-timestamp --directory ${untarDir} -zxf ${localArchiveFilePath}"
trace "untaring file ${localArchiveFilePath}"
trace ${cmd}; ${cmd}

if [[ $? != 0 ]]; then
    echo "${thisScript}: error untaring file ${localArchiveFilePath}"
    exit 1
fi

if [[ ! -d ${releaseDir} ]]; then
    echo "${thisScript}: could not find directory ${releaseDir}"
    exit 1  
fi

# Start transaction
cmd="sudo cvmfs_server transaction ${cvmfsRepoName}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
    echo "${thisScript}: could not start cvmfs_server transaction"
    exit 1
fi

# Copy this release to its destination directory
baseProductDir=$(dirname ${targetDir})
if [[ ! -d ${baseProductDir} ]]; then
   cmd="sudo mkdir -p ${baseProductDir}"
   trace ${cmd}; ${cmd}
   if [[ $? != 0 ]]; then
       echo "${thisScript}: could not create base product directory ${baseProductDir}"
       cmd="sudo cvmfs_server abort -f ${cvmfsRepoName}"
       trace ${cmd}; ${cmd}
       exit 1
   fi
fi

cmd="sudo cp -pR ${releaseDir} ${baseProductDir}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
    echo "${thisScript}: could not copy release to its destination directory ${baseProductDir}"
    cmd="sudo cvmfs_server abort -f ${cvmfsRepoName}"
    trace ${cmd}; ${cmd}
    exit 1
fi

# Change file ownership
fileOwner="lsstsw"
if getent passwd ${fileOwner} > /dev/null 2>&1; then
    cmd="sudo chown ${fileOwner}:${fileOwner} ${baseProductDir}"
    trace ${cmd}; ${cmd}
    cmd="sudo chown -R ${fileOwner}:${fileOwner} ${targetDir}"
    trace ${cmd}; ${cmd}
fi

# Commit this transaction and publish the modifications
cmd="sudo cvmfs_server publish ${cvmfsRepoName}"
trace ${cmd}; ${cmd}
if [[ $? != 0 ]]; then
    echo "${thisScript}: could not commit transaction"
    cmd="sudo cvmfs_server abort -f ${cvmfsRepoName}"
    trace ${cmd}; ${cmd}
    exit 1
fi

# Clean up
trace "cleaning up"
cmd="sudo rm -rf ${untarDir} ${downloadDir}"
trace ${cmd}; ${cmd}

trace "done"
exit 0
