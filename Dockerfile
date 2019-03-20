FROM centos:centos7

LABEL maintainer="Fabio Hernandez <fabio@in2p3.fr>" \
	keywords="CernVM-FS,cvmfs,lsst,binary distribution" \
	purpose="Base image for building the LSST software framework for \
distribution via CernVM-FS"

#
# Install pre-requisites for building the stack
# Reference document: https://pipelines.lsst.io/install/prereqs/centos.html
#
RUN yum install -q -y \
   bison \
   blas \
   bzip2 \
   bzip2-devel \
   cmake \
   curl \
   flex \
   fontconfig \
   freetype-devel \
   gawk \
   gcc-c++ \
   gcc-gfortran \
   gettext \
   git \
   glib2-devel \
   java-1.8.0-openjdk \
   libcurl-devel \
   libuuid-devel \
   libXext \
   libXrender \
   libXt-devel \
   make \
   mesa-libGL \
   ncurses-devel \
   openssl-devel \
   patch \
   perl \
   perl-ExtUtils-MakeMaker \
   readline-devel \
   sed \
   tar \
   which \
   zlib-devel

#
# Install additional packages useful for the build system
#
RUN yum install -q -y redhat-lsb unzip
RUN yum install -q -y centos-release-scl
RUN yum install -q -y devtoolset-6

#
# Create non-privileged user
#
ENV username="lsstsw"
RUN useradd --create-home --uid 361 --user-group --home-dir /home/${username} ${username}

#
# Add build scripts
#
WORKDIR /home/${username}
ADD ["functions.sh", "makeStack.sh", "buildStack.sh", "enableDevtoolset.bash", "upload.sh", "condaExtraPackages.txt", "./"]

CMD /bin/bash