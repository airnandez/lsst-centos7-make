#!/bin/bash 

#
# Init
#
thisScript=`basename $0`

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

#
# We need the rclone credentials for the upload to succeed
#
if [ -z "${RCLONE_CREDENTIALS}" ]; then
	echo "${thisScript}: environment variable RCLONE_CREDENTIALS not set or empty"
	exit 1
fi

#
# Set temporary directory
#
USER=${USER:-`id -un`}
mkdir -p /dev/shm/$USER/tmp && chmod g-rwx,o-rwx /dev/shm/$USER/tmp
TMPDIR="/dev/shm/$USER/tmp"

#
# Download and install rclone executable
#
rcloneUrl="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
curl -s -OL ${rcloneUrl} ${TMPDIR}
rm -rf ${TMPDIR}/rclone && unzip -qq -d ${TMPDIR}/rclone rclone-current-linux-amd64.zip 
rcloneExe=`find ${TMPDIR}/rclone -name rclone -type f -print`
chmod u+x ${rcloneExe}

#
# Create a rclone.conf file with appropriate permissions
#
rcloneConfFile=${TMPDIR}/.rclone.conf
echo ${RCLONE_CREDENTIALS} | base64 -d > ${rcloneConfFile} && chmod g-rwx,o-rwx ${rcloneConfFile}

#
# Upload the archive file to its destination bucket
#
bucket="cc:sandbox"
destination="${bucket}/py3"
re=".*-py2.*"
if [[ ${archiveFile} =~ $re ]]; then
   destination="${bucket}/py2"
fi

${rcloneExe} --config ${rcloneConfFile} copy ${archiveFile} ${destination}/`basename ${archiveFile}`

exit $?