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
#        -U  don't upload resulting archive file                              #
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
os=$(osName)
TMPDIR=${TMPDIR:-/tmp}
useBinaries=false
doUpload=true
doCompressArchive=true

#
# Routines
#
usage () {
    echo "Usage: ${thisScript}  -p <products>  -b <build directory>  -a <archive directory> [-Z] [-U] -t <tag>"
}

# Start execution
trace "$0" "$*"

#
# Parse and verify command line arguments
#
while getopts p:b:a:t:UZ optflag; do
    case $optflag in
        p)
            products=${OPTARG//,/ }
            ;;
        b)
            buildDir=$(readlink -f "${OPTARG}")
            ;;
        a)
            archiveDir=$(readlink -f "${OPTARG}")
            ;;
        t)
            tag=${OPTARG}
            ;;
        Z)
            useBinaries=true
            ;;
        U)
            doUpload=false
            ;;
        *)
            echo "${thisScript}: unexpected option ${optflag}"
            usage
            exit 1
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
    echo "${thisScript}: cannot run as root"
    exit 1
fi


#
# Is the provided tag a stable version or a weekly version?
#
if ! $(isValidTag ${tag}); then
    echo "${thisScript}: '${tag}' is not a recognized version tag"
    exit 1
fi


#
# Download the installer
#
url="https://raw.githubusercontent.com/lsst/lsst/main/scripts/lsstinstall"  # or use redirector https://ls.st/lsstinstall
status=$(curl --silent --head ${url} | head -n 1)
if [[ ${status} != HTTP*200* ]]; then
    echo "${thisScript}: could not find installer at ${url}"
    exit 1
fi
cd ${buildDir}
cmd="curl --silent --location --remote-name ${url}"
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
#    10.15  Catalina
#    11     Big Sur
#    12     Monterey
#
if [[ ${os} == "darwin" ]]; then
    export MACOSX_DEPLOYMENT_TARGET="10.9"
fi

#
# Remove conda & mamba configuration files as well as astropy cache
#
rm -rf ${HOME}/.conda ${HOME}/.condarc ${HOME}/.mambarc ${HOME}/.astropy ${HOME}/.lsst/astropy

#
# Bootstrap the installation. After executing the bootstrap script, there must
# be a file 'loadLSST.bash'
#
releaseDir=$(basename ${buildDir})
export TMPDIR=$(mktemp -d $TMPDIR/${releaseDir}-build-XXXXXXXXXX)
installerFlags="-B"  # Do not use binaries
[[ ${useBinaries} == true ]] && installerFlags="-S" # Do not use sources

case ${os} in
    "linux")
        cmd="bash lsstinstall -P -X ${tag} -d ${installerFlags}"
        ;;
    "darwin")
        cmd="bash lsstinstall -P -T ${tag} -d ${installerFlags}"
        ;;
    *)
        echo "${thisScript}: unsupported operating system ${os}"
        exit 1
esac

trace $cmd ; $cmd
if [[ ! -f "loadLSST.bash" ]]; then
    echo "${thisScript}: file 'loadLSST.bash' not found"
    exit 1
fi

#
# Source minimal LSST environment
#
trace "activating minimal LSST environment via loadLSST.bash"
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
if [ $? != 0 ]; then
    echo "${thisScript}: shebangtron failed"
    exit 1
fi
trace "shebangtron finished"

#
# Configure EUPS site startup file
#
trace "configuring EUPS site startup file"
eupsPath=${EUPS_PATH:-${buildDir}/stack/current}
eupsPath=$(echo ${eupsPath} | awk -F ':' '{print $1}')
mkdir -p ${eupsPath}/site
cat >> ${eupsPath}/site/startup.py <<-EOF
# Configure EUPS not to try to acquire locks on a read-only file system
hooks.config.site.lockDirectoryBase = None
EOF

#
# Execute "conda init shell", for conda 22.9.0
# (see: https://github.com/conda/conda/issues/11885)
#
if [[ $(conda --version) =~ "conda 22.9" ]]; then
    cmd="conda init bash zsh fish"
    trace $cmd ; $cmd
fi

#
# Install conda packages not included in distribution
# The extra packages to install are specified in a text file to be consumed
# by the 'conda install' command. Each line of that file contains the name
# of a package. When installing those extra packages we make sure not to
# modify dependencies which are the conda packages on top of which the
# version of the LSST software has been tested against.
#
didCreateEnvironment=false
condaExtendedEnvironment="${thisScriptDir}/conda-extended-$(platform).env"
if [ -f ${condaExtendedEnvironment} ]; then
    # Filter out comments and check if there are actually packages to install
    grep -v '^\s*#' ${condaExtendedEnvironment} > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        # Configure conda
        cmd="conda --version"
        trace $cmd ; $cmd
        cmd="conda info --envs"
        trace $cmd ; $cmd
        # cmd="conda config --add channels conda-forge"
        # trace $cmd ; $cmd
        # cmd="conda config --set channel_priority strict"
        # trace $cmd ; $cmd

        # Create and activate a new conda environment before
        # installing additional packages
        baseEnv=${CONDA_DEFAULT_ENV}
        extendedEnv="${baseEnv}-ext"
        trace "creating ${extendedEnv} conda environment"
        cmd="mamba --no-banner create --name ${extendedEnv} --clone ${baseEnv}"
        trace $cmd ; $cmd
        if [ $? != 0 ]; then
            echo "${thisScript}: could not create ${extendedEnv}"
            exit 1
        fi

        trace "activating ${extendedEnv} environment"
        cmd="conda activate ${extendedEnv}"
        trace $cmd ; $cmd
        if [ $? != 0 ]; then
            echo "${thisScript}: could not activate ${extendedEnv}"
            exit 1
        fi

        trace "installing extra conda packages"
        cmd="mamba --no-banner install --channel conda-forge --quiet --yes --file ${condaExtendedEnvironment}"
        trace $cmd ; $cmd
        if [ $? != 0 ]; then
            # Could not install extra packages into the newly created environment
            # Revert to the original environment
            echo "${thisScript}: could not install conda extensions into environment ${extendedEnv}"
            echo "${thisScript}: reactivating base environment ${baseEnv}"
            cmd="conda activate ${baseEnv}"
            trace $cmd ; $cmd
            if [ $? != 0 ]; then
                echo "${thisScript}: could not reactivate conda environment ${baseEnv}"
                exit 1
            fi

            # Remove the newly created environment
            echo "${thisScript}: removing extended environment ${extendedEnv}"
            cmd="mamba env remove --name ${extendedEnv}"
            trace $cmd ; $cmd
        else
            didCreateEnvironment=true
        fi
    fi
fi

#
# Perform generic post-installation steps
#
jupyterCmd=$(command -v jupyter)
if [[ -n "${jupyterCmd}" ]]; then
    #
    # Build Jupyter Lab source extensions
    #
    cmd="${jupyterCmd} lab build"
    trace $cmd ; $cmd
fi

#
# Create adapted versions of loadLSST.*sh for activating the extended conda environment by default (if any)
# For instance, replace the line
#    export LSST_CONDA_ENV_NAME=${LSST_CONDA_ENV_NAME:-lsst-scipipe-0.7.0}
# by the extended environment
#    export LSST_CONDA_ENV_NAME='lsst-scipipe-0.7.0-ext'
if [[ ${didCreateEnvironment} = true ]]; then
    tmpFile=$(mktemp)
    trap "rm -f ${tmpFile}" EXIT

    subsExpr="s|^export LSST_CONDA_ENV_NAME=.*$|export LSST_CONDA_ENV_NAME=\'${CONDA_DEFAULT_ENV}\'|1"
    for file in loadLSST.*sh; do
        trace "adapting ${file}"
        if [[ ${file} =~ loadLSST\.(ash|bash|fish|sh|zsh) ]]; then
            sed -e "${subsExpr}" ${file} > ${tmpFile}
            extendedFile="${file%.*}-ext.${file##*.}"
            cp ${tmpFile} ${extendedFile}
            chmod u=rw-,go=r-- ${extendedFile}
        fi
    done
fi


#
# Add README file for this version
#
trace "creating README.txt"
cat > ${buildDir}/README.txt <<-EOF
LSST Science Pipelines
----------------------

Product(s):          ${products}
Tag:                 ${tag}
Build time:          $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build platform:      $(osDescription)
conda:               $(conda --version)
mamba:               $(mamba --version | grep mamba)
conda environment:   ${baseEnv:-${CONDA_DEFAULT_ENV}}
Python interpreter:  $(pythonDescription)
C++ compiler:        $(cppDescription)
Documentation:       https://pipelines.lsst.io
                     https://sw.lsst.eu
EOF

#
# Add .cvmfscatalog when building for distribution via CernVM FS
#
if [[ ${buildDir} =~ /cvmfs ]]; then
    # Add an empty '.cvmfscatalog' file at the top of this release
    trace "creating .cvmfscatalog file"
    cmd="touch ${buildDir}/.cvmfscatalog"
    trace $cmd ; $cmd

    # Add an empty '.cvmfscatalog' file at the root directory of
    # each conda environment
    trace "creating .cvmfscatalog files for each conda environment"
    for dir in $(conda env list | awk '/^lsst-scipipe-*/ {print $NF}'); do
        cmd="touch ${dir}/.cvmfscatalog"
        trace $cmd ; $cmd
    done
fi


#
# Make archive file
#
trace "building archive file"
archiveExtension=".tar"
if [[ ${doCompressArchive} == true ]]; then
    extraTarOpts=" -z "
    archiveExtension="${archiveExtension}.gz"
fi
tarFileName="${releaseDir}.${archiveExtension}" # e.g. w_2024_35.tar.gz, w_2024_35-dev.tar.gz or v27.0.0.tar.gz
archiveFile=${archiveDir}/${tarFileName}
tarCmd="tar"
if [[ ${os} == "darwin" ]]; then
    tarCmd="gnutar"
fi
# TODO: remove the 'echo' below
cmd="echo ${tarCmd} --directory $(dirname ${buildDir}) --hard-dereference ${extraTarOpts} -cf ${archiveFile} $(basename ${buildDir})"
trace $cmd ; $cmd
if [ $? != 0 ]; then
    echo "${thisScript}: error creating archive ${archiveFile}"
    exit 1
fi


#
# Upload archive file
#
if [[ ${doUpload} == true ]]; then
    # Compute the destination. It is of the form
    #    rubin:software/cvmfs/sw.lsst.eu/almalinux-x86_64/lsst_distrib/w_2024_35.tar.gz
    destination="${bucket}$(dirname ${buildDir})/${tarFileName}"
    uploadExe="${thisScriptDir}/upload.sh"
    if [[ -x "${uploadExe}" ]]; then
        trace "uploading archive file ${archiveFile} to ${destination}"
        cmd="${uploadExe} ${archiveFile} ${destination}"
        trace $cmd; $cmd
    else
        trace "file ${uploadExe} not executable or not found"
    fi
else
    trace "upload disabled: skipping upload of of ${archiveFile}"
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
