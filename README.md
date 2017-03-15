# Containerized build of LSST software framework

## Introduction

This repository contains tools for building the LSST software framework from sources in a containerized environment.

The output of the build process is a `.tar.gz` file that can be deployed and distributed via [CernVM-FS](https://github.com/airnandez/lsst-cvmfs) or deployed in a local file system.

## Dependencies

You need Docker installed in the host you want to build the LSST software on. Instructions for installing Docker on Linux can be found [here](https://docker.github.io/engine/installation/). We have tested using Docker `v1.12.1` on a host runing CentOS 7.

_Warning: This method of building the LSST software has only been tested on Linux but it may also work on macOS_.

## How to use

**1) Clone this repository**

```
git clone https://github.com/airnandez/lsst-centos7-make
cd lsst-centos7-make
```

**2) Prepare the container image**

You can either download the container image or build it from scratch. To download it from the Docker registry do:

```bash
docker pull airnandez/lsst-centos7-make
```

Alternatively, build the image from scratch:

```bash
bash buildImage.sh
```

**3) Build a specific version of LSST software distribution**

You must specify the version of the LSST software you want to build. For instance, to build version `v13_0` do:

```bash
bash runContainer.sh -t v13_0
```

This method by default expect the directory `/scratch` to exist in the host and will make it accessible to the container. This directory is exposed by the host to the container to save, among other things, the final output of the build process as well as some temporary files created during the build process. You can specify which work directory from the host the container should use during the build process, via the flag `-v /path/to/host/work/directory`, for instance:

```bash
bash runContainer.sh -v /mnt -t v13_0
```

By default, the LSST software built this way will is meant to be deployed via CernVM-FS under the path `/cvmfs/lsst.in2p3.fr/...`. To build the software for deployment in another directory, say `/my/deploy/top/dir`, use the option `-d`, for example:

```bash
bash runContainer.sh  -d /my/deploy/top/dir  -t v13_0
```

**4) Build an extended version of LSST framework**

By default these tools build from source the official package `lsst_distrib`. In addition, you can build packages available in the LSST package repository but not already included in `lsst_distrib` via the `-p` option. For instance, to add the packages `my_package1` and `my_package2` do:

```bash
bash runContainer.sh  -p my_package1,my_package2  -t v13_0 
```

Note that the base package, i.e. `lsst_distrib` is always built.

## Credits

### Author
These tools were developed and are maintained by Fabio Hernandez at [IN2P3 / CNRS computing center](http://cc.in2p3.fr) (Lyon, France).

## License
Copyright 2017 Fabio Hernandez

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.


