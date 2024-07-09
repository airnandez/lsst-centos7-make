FROM almalinux:9.4

LABEL maintainer="Fabio Hernandez <fabio@in2p3.fr>" \
	keywords="CernVM-FS,cvmfs,lsst,binary distribution" \
	purpose="Base image for building the LSST software framework for \
distribution via CernVM-FS"

#
# Update the operating system
#
RUN yum update --quiet --assumeyes

#
# Install pre-requisites for building the stack
# Reference: https://pipelines.lsst.io/install/prereqs.html#system-prerequisites
#
RUN yum install --quiet --assumeyes patch diffutils git

#
# Install additional packages necessary for this build system
#
RUN yum install --quiet --assumeyes unzip

#
# Create non-privileged user
#
ENV username="lsstsw"
RUN useradd --create-home --uid 361 --user-group --home-dir /home/${username} ${username}

#
# Add build scripts
#
WORKDIR /home/${username}
ADD --chown=lsstsw:lsstsw ["functions.sh", "makeStack.sh", "buildStack.sh", "enableDevtoolset.bash", "upload.sh", "conda-extended-*.env", "./"]
RUN ["/bin/chmod", "ugo+rx", "makeStack.sh", "buildStack.sh", "enableDevtoolset.bash", "upload.sh"]

CMD /bin/bash
