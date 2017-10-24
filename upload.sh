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

if [ ! -f "${archiveFile}" ]; then
    echo "${thisScript}: file ${archiveFile} not found"
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
TMPDIR="/dev/shm/$USER/tmp"
mkdir -p ${TMPDIR} && chmod g-rwx,o-rwx ${TMPDIR}

#
# Download and install rclone executable
#
rcloneUrl="https://downloads.rclone.org/rclone-current-linux-amd64.zip"
rcloneZipFile=${TMPDIR}/rclone-current-linux-amd64.zip
rm -rf ${rcloneZipFile}
curl -s -L -o ${rcloneZipFile} ${rcloneUrl}
if [ $? -ne 0 ]; then
	echo "${thisScript}: error downloading rclone"
	exit 1
fi
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

${rcloneExe} -I --config ${rcloneConfFile} copy ${archiveFile} ${destination}
rc=$?

#
# Remove rclone config file
#
rm -rf ${rcloneConfFile}

exit $rc