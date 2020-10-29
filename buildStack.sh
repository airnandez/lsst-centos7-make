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
#                  [-Z] -t <tag>                                              #
#                                                                             #
#    where:                                                                   #
#        <products> is the comma-separated list of EUPS products to be        #
#            installed, e.g. "lsst_distrib".                                  #
#                                                                             #
#        <build directory> is the absolute path of the directory the stack    #
#            will be built into. This directory must exist and be writable.   #
#                                                                             #
#        <archive directory> is the absolute path of the directory to store   #
#            an archive file (.tar.gz) of the stack just built.               #
#                                                                             #
#        <tag> is the tag of the EUPS product to be installed.                #
#                                                                             #
#        -Z  allow EUPS to use binary tarballs (if available)                 #
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
thisScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
user=$(whoami)
os=$(osName)
TMPDIR=${TMPDIR:-/tmp}
useBinaries=false
pythonVersion="3"

#
# Routines
#
usage () { 
    echo "Usage: ${thisScript}  -p products  -b <build directory>  -a <archive directory>  -Y <python version> [-Z] -t <tag>"
}

# Start execution
trace "$0" "$*"

#
# Parse and verify command line arguments
#
while getopts p:b:a:t:Z optflag; do
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
        Z)
            useBinaries=true
            ;;
    esac
done
shift $((OPTIND - 1))

if [[ -z "${buildDir}" || -z "${archiveDir}" || -z "${tag}" || -z "${products}" ]]; then
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


#
# Is the provided tag a stable version or a weekly version?
#
if [[ ${tag} =~ ^v[0-9]+_[0-9]+.*$ ]]; then
    # Stable version tag of the form 'v12_1'
    # The suffix will be of the form 'v12.1'
    suffix=${tag//_/.}
elif [[ ${tag} =~ ^w_[0-9]{4}_[0-9]{1,2}$ ]]; then
    # Weekly version tag of one of the forms 'w_2017_3' or 'w_2016_15'
    # The suffix will be identical to the weekly tag
    # The github tag has the form: w.2017.5
    suffix=${tag}
elif [[ ${tag} =~ ^sims_.*$ ]]; then
    # This is a lsst_sims tag.
    # The suffix will be identical to the tag
    suffix=${tag}
else
    echo "${thisScript}: '${tag}' is not a recognized version tag"
    exit 1
fi

#
# Set the environment for building this release
#
# From w_2020_18 the compilers needed for building and running lsst_distrib
# are included in the conda distribution, so we don't need a devtoolset
# TODO: disable/enable the devtools in a more dynamic way
doEnableDevTools=false
if [[ ${doEnableDevTools} = true && -f ${HOME}/enableDevtoolset.bash ]]; then
    requiredDevToolSet=$(scl -l | tail -1)
    trace "activating ${requiredDevToolSet}"
    source ${HOME}/enableDevtoolset.bash ${requiredDevToolSet}
fi

#
# Download the bootstrap installer from the canonical repository
#
url="https://raw.githubusercontent.com/lsst/lsst/master/scripts/newinstall.sh"
status=$(curl -s --head  ${url} | head -n 1)
if [[ ${status} != HTTP*200* ]]; then
    echo "${thisScript}: download installer could not be found at ${url}"
    exit 1
fi
cd ${buildDir}
cmd="curl -s -L -o newinstall.sh ${url}"
trace "working directory" $(pwd)
trace $cmd ; $cmd

#
# Set deployment target for OS X
#    10.9   Mavericks
#    10.10  Yosemite
#    10.11  El Capitan
#    10.12  Sierra
#    10.13  High Sierra
#    10.14  Mojave
#
if [[ ${os} == "darwin" ]]; then
    export MACOSX_DEPLOYMENT_TARGET="10.9"
fi

#
# Bootstrap the installation. After executing the bootstrap script, there must
# be a file 'loadLSST.bash'
#
[[ ${useBinaries} == true ]] && useTarballsFlag="-t"
export TMPDIR=$(mktemp -d $TMPDIR/${suffix}-build-XXXXXXXXXX)
cmd="bash newinstall.sh -b -s ${useTarballsFlag}"
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
# Download and build the requested products
#
products=$(echo ${products} | sed -e 's/,/ /g')
for p in ${products}; do
    cmd="eups distrib install -t ${tag} ${p}"
    trace $cmd ; $cmd
    if [ $? != 0 ]; then
        echo "${thisScript}: command ${cmd} failed"
        exit 1
    fi
done

#
# Install conda packages not included in distribution
# The extra packages to install are specified in a text file to be consumed
# by the 'conda install' command. Each line of that file contains the name
# of a package. When installing those extra packages we make sure to not
# modify dependencies which are the conda packages on top of which the
# version of the LSST software has been tested against.
#
condaExtensionsFile="${thisScriptDir}/condaExtraPackages.txt"
if [ -f ${condaExtensionsFile} ]; then
    # Filter out comments and check if there are actually packages to install
    grep -v '^\s*#' ${condaExtensionsFile} > /dev/null 2>&1
    if [ $? -eq 0 ]; then

        # On macOS we need to create and activate a conda environment before
        # installing new packages, to avoid conda not being able to resolve
        # conflicts
        if [[ ${os} == "darwin" ]]; then
            trace "creating rubinenv conda environment"
            cmd="conda create -n rubinenv -c conda-forge rubinenv"
            trace $cmd ; $cmd
            if [ $? != 0 ]; then
                echo "${thisScript}: could not create rubinenv"
                exit 1
            fi

            trace "activating rubinenv environment"
            cmd="conda activate rubinenv"
            trace $cmd ; $cmd
            if [ $? != 0 ]; then
                echo "${thisScript}: could not activate rubinenv"
                exit 1
            fi
        fi

        trace "installing conda extra packages"
        cmd="conda install --no-update-deps --quiet --yes --file=${condaExtensionsFile}"
        trace $cmd ; $cmd
        if [ $? != 0 ]; then
            echo "${thisScript}: could not install conda extensions"
            exit 1
        fi
    fi
fi

#
# Perform generic post-installation steps
#

#
# Update the Python interpreter path of EUPS installed products: we need to perform
# this step for both Linux and macOS
#
trace "applying shebangtron"
shebangtron=${TMPDIR}/shebangtron
curl -sSL -o ${shebangtron} "https://raw.githubusercontent.com/lsst/shebangtron/master/shebangtron"
if [[ ! -f ${shebangtron} ]]; then
    echo "${thisScript}: file ${shebangtron} not found"
    exit 1
fi
cmd="python ${shebangtron}"
trace $cmd; $cmd
trace "shebangtron finished"

#
# Perform OS-specific post-installation
#
if [[ ${os} == "linux" ]]; then
    #
    # Extend the loadLSST.bash to enable devtoolset if necessary
    #
    if [[ ${doEnableDevTools} = true ]]; then
        trace "modifying loadLSST.bash for devtoolset"
        if [[ -f ${HOME}/enableDevtoolset.bash ]]; then
            cp ${HOME}/enableDevtoolset.bash ${buildDir}
            chmod ugo-x ${buildDir}/enableDevtoolset.bash
            cat >> loadLSST.bash <<-EOF

# Enable the C++ compiler runtime required by this release, if available (see README.txt for details)
[[ -f \${LSST_HOME}/enableDevtoolset.bash ]] && source \${LSST_HOME}/enableDevtoolset.bash ${requiredDevToolSet}
EOF
       fi
    fi
fi

#
# Add README file for this version
#
trace "creating README.txt"
cat > ${buildDir}/README.txt <<-EOF
LSST Software
-------------

Product(s):          ${products}
Tag:                 ${tag}
Build time:          $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build platform:      $(osDescription)
Python interpreter:  $(pythonDescription)
C++ compiler:        $(cppDescription)
Conda:               $(conda --version)
Documentation:       https://sw.lsst.eu
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
# Add .cvmfscatalog when building for distribution via CernVM FS
#
if [[ ${buildDir} =~ /cvmfs ]]; then
    trace "creating .cvmfscatalog file"
    cmd="touch ${buildDir}/.cvmfscatalog"
    trace $cmd ; $cmd
fi

#
# Change permissions for this installation
#
trace "modifying permissions under ${buildDir}"
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
tarFileName=$(echo ${buildDir}-py${pythonVersion}-$(platform).tar.gz | cut -b 2- | sed -e 's|/|__|g')
archiveFile=${archiveDir}/${tarFileName}
cd ${buildDir}/..
cmd="${tarCmd} --hard-dereference -zcf ${archiveFile} ./$(basename ${buildDir})"
trace $cmd ; $cmd
if [ $? != 0 ]; then
    echo "${thisScript}: error creating archive ${archiveFile}"
    exit 1
fi

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
