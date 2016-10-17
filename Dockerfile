FROM centos:centos7

MAINTAINER Fabio Hernandez <fabio@in2p3.fr>
LABEL purpose="Base image for building the LSST software framework for \
distribution via CernVM-FS" \
keywords="CernVM-FS,cvmfs,lsst,binary distribution"

#
# Install pre-requisites for building the stack
# Reference document: https://pipelines.lsst.io/install/newinstall.html
#
RUN yum install -q -y bison curl blas bzip2-devel bzip2 flex fontconfig \
    freetype-devel gcc-c++ gcc-gfortran git libuuid-devel               \
    libXext libXrender libXt-devel make openssl-devel patch perl        \
    readline-devel tar zlib-devel ncurses-devel cmake glib2-devel       \
    java-1.8.0-openjdk gettext perl-ExtUtils-MakeMaker

#
# Create non-privileged user
#
ENV username="lsstsw"
RUN useradd --create-home --user-group --home-dir /home/${username} ${username}

#
# Add build script
#
WORKDIR /home/${username}
ADD ["makeStack.sh", "."]

CMD /bin/bash