#!/bin/bash 

#
# Init
#
thisScript=$(basename $0)
os=$(uname -s | tr [:upper:] [:lower:])

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
USER=${USER:-$(id -un)}
TMPDIR=${TMPDIR:-"/tmp"}
mkdir -p ${TMPDIR}
if [ ${os} == "darwin" ]; then
    TMPDIR=$(mktemp -d ${TMPDIR}/${USER}.upload.XXXXX)
else
    TMPDIR=$(mktemp -d -p ${TMPDIR} ${USER}.upload.XXXXX)
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
rcloneExe=$(find ${unzipDir} -name rclone -type f -print)
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
# Upload the archive file to its destination bucket.
# We use two buckets: 'stables' for stable versions and 'weeklies' for weekly versions
# Archive files names with a pattern such as 'w_2018_14' are uploaded to 'weeklies' and
# archive files named with a pattern like 'v15' are uploaded to 'stables'
#
archiveBasename=$(basename ${archiveFile})
if [[ ${archiveBasename} =~ \.*v[0-9].*- ]]; then
    bucket="cc:stables"
else
    bucket="cc:weeklies"
fi
if [[ ${archiveBasename} =~ \.*-py3-\.* ]]; then
    destination="${bucket}/py3"
else
    destination="${bucket}/py2"
fi

cmd="${rcloneExe} -I --config ${rcloneConfFile} copy ${archiveFile} ${destination}"
echo $cmd
$cmd
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