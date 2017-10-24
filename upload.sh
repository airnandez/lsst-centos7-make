#!/bin/bash 

#
# Init
#
thisScript=`basename $0`
os=`uname -s | tr [:upper:] [:lower:]`

usage () { 
    echo "Usage: ${thisScript} <archive file>"
}

#
# Archive file name needs to be received as argument
#
archiveFile=$1
if [ -z "${archiveFile}" ]; then
	usage
	exit 1
fi

if [ ! -f "${archiveFile}" ]; then
    echo "${thisScript}: file ${archiveFile} not found"
    exit 1
fi

#
# We need the rclone credentials for the upload to succeed or a $HOME/.rclone.conf file
#
if [ -z "${RCLONE_CREDENTIALS}" ] && [ ! -f "$HOME/.rclone.conf" ]; then
    echo "${thisScript}: environment variable RCLONE_CREDENTIALS not set or empty and $HOME/.rclone.conf not found"
    exit 1
fi

#
# Prepare temporary directory
#
USER=${USER:-`id -un`}
if [ ${os} == "darwin" ]; then
    TMPDIR=`mktemp -d /tmp/$USER.XXXXX`
else
    TMPDIR=`mktemp -d -p /dev/shm/$USER tmp.XXXXX`
fi

#
# Download rclone executable
#
rcloneUrl="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
if [ ${os} == "darwin" ]; then
    rcloneUrl="https://downloads.rclone.org/rclone-current-osx-amd64.zip"
fi
rcloneZipFile=${TMPDIR}/rclone-current-amd64.zip
rm -rf ${rcloneZipFile}
curl -s -L -o ${rcloneZipFile} ${rcloneUrl}
if [ $? -ne 0 ]; then
	echo "${thisScript}: error downloading rclone"
	exit 1
fi

#
# Unpackage rclone and make it ready for execution
#
unzipDir=${TMPDIR}/rclone
rm -rf ${unzipDir}
unzip -qq -d ${unzipDir} ${rcloneZipFile}
rcloneExe=`find ${unzipDir} -name rclone -type f -print`
if [[ ! -f ${rcloneExe} ]]; then
	echo "${thisScript}: could not find rclone executable at ${rcloneExe}"
	exit 1
fi
chmod u+x ${rcloneExe}

#
# Create a rclone.conf file with appropriate permissions
#
if [ -f "$HOME/.rclone.conf" ]; then
    rcloneConfFile="$HOME/.rclone.conf"
    eraseRcloneConf="false"
else
    eraseRcloneConf="true"
    rcloneConfFile=${TMPDIR}/.rclone.conf
    echo ${RCLONE_CREDENTIALS} | base64 -d > ${rcloneConfFile} && chmod g-rwx,o-rwx ${rcloneConfFile}
fi

#
# Upload the archive file to its destination bucket
#
bucket="cc:sandbox"
destination="${bucket}/py3"
re=".*-py2.*"
if [[ ${archiveFile} =~ $re ]]; then
   destination="${bucket}/py2"
fi

${rcloneExe} -I --config ${rcloneConfFile} copy ${archiveFile} ${destination}
rc=$?

#
# Remove rclone config file, if needed
#
if [ ${eraseRcloneConf} = "true" ]; then
    rm -f ${rcloneConfFile}
fi

#
# Clean up
#
rm -rf ${TMPDIR}

exit $rc