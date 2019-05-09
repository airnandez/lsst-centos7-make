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
#    makeStack.sh [-u <user>]  [-d <target directory>]  [-B <base product>]   #
#                 [-p products] [-Y <python version>]  [-x <extension>]       #
#                 [-Z] -t <tag>                                               #
#                                                                             #
#    where:                                                                   #
#        <user> is the username which will own the software built.            #
#            Default: "lsstsw" on linux, current user on OS X                 #
#                                                                             #
#        <base product> is the identifier of the base product to install,     #
#            such as "lsst_distrib" or "lsst_sims".                           #
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
#        <products> is the comma-separated list of EUPS products to be        #
#            installed in addition to the base product. The base product      #
#            is always installed first.                                       #
#            Default: ""                                                      #
#                                                                             #
#        <python version> version of the Python interpreter to be installed   #
#            valid values are "2" or "3".                                     #
#            Default: "3"                                                     #
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
source 'functions.sh'

#
# Init
#
thisScript=$(basename $0)
user="lsstsw"
os=$(osName)
if [[ $os == "darwin" ]]; then
    user=$USER
fi
targetDir="/cvmfs/sw.lsst.eu/$(platform)"
baseProduct="lsst_distrib"
pythonVersion="3"
useBinaries=false
isExperimental=false
experimentalExt="dev"

#
# usage()
#
usage () { 
    echo "Usage: ${thisScript} [-u <user>] [-d <target directory>] [-B <base product>] [-p <products>] [-Y <python version>] [-Z] [-X] -t <tag>"
} 

#
# Parse command line arguments
#
while getopts d:t:u:B:p:Y:x:ZX optflag; do
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
        B)
            baseProduct=${OPTARG}
            ;;
        p)
            optProducts=${OPTARG}
            ;;
        Y)
            pythonVersion=${OPTARG}
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

#
# Is the provided tag a stable release or a weekly release?
#
if [[ ${tag} =~ ^v[0-9]+_[0-9]+.*$ ]]; then
    # Stable release tag of the form 'v12_1'
    # The name of the release directory will be of the form 'v12.1'
    releaseDir=${tag//_/.}
elif [[ ${tag} =~ ^w_[0-9]{4}_[0-9]{1,2}$ ]]; then
    # Weekly release tag of one of the forms 'w_2017_3' or 'w_2016_15'
    # The name of the release directory will be identical to the weekly tag
    releaseDir=${tag}
elif [[ ${tag} =~ ^sims_.*$ ]]; then
    # This is a lsst_sims tag.
    # The name of the release directory will be identical to the tag
    releaseDir=${tag}
else
    echo "${thisScript}: '${tag}' is not a recognized version tag"
    exit 1
fi

# If this is a build for an experimental release add a marker to the directory
[[ ${isExperimental} == true ]] && releaseDir="${releaseDir}-${experimentalExt}"

#
# Create the build directory: the build directory depends on the specified target
# directory. The build directory ends like "lsst_distrib/v13.0" or "lsst_distrib/w_2017_10".
#
buildDir=${targetDir}/${baseProduct}/${releaseDir}
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
logFile=${logDir}/${baseProduct}-${tag}-py${pythonVersion}.log
if [[ ${isExperimental} == true ]]; then
   logFile=${logDir}/${baseProduct}-${tag}-${experimentalExt}-py${pythonVersion}.log
fi
rm -rf ${logFile}
touch ${logFile}

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
[[ ${useBinaries} == true ]] && binaryFlag="-Z"
if [[ $(whoami) == ${user} ]]; then
    (./buildStack.sh -p ${products} -b ${buildDir} -a ${archiveDir} -Y ${pythonVersion} ${binaryFlag} -t ${tag}) < /dev/null  >> ${logFile}  2>&1
    rc=$?
else
    (su "${user}" -c "./buildStack.sh -p ${products} -b ${buildDir} -a ${archiveDir} -Y ${pythonVersion} ${binaryFlag} -t ${tag}") < /dev/null  >> ${logFile}  2>&1
    rc=$?
fi

exit ${rc}
