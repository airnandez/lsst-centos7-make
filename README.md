# Containerized build of LSST software framework

## Introduction

This repository contains tools for building the LSST software framework from sources in a containerized environment.

The output of the build process is a `.tar.gz` file that can be deployed via [distributed via CernVM-FS](https://github.com/airnandez/lsst-cvmfs) or installed in a local file system.

## Dependencies

You need Docker installed in the host you want to build the LSST software on. Instructions for installing Docker on Linux can be found [here](https://docker.github.io/engine/installation/). We have tested using Docker `v1.12.1` on a host runing CentOS 7.

_Warning: This method of building the LSST software has only been tested on Linux but it may also work on macOS_.

## How to use

**1) Pull the container image:**

```
docker pull airnandez/lsst-centos7-make
```

**2) Clone this repository:**

```
git clone https://github.com/airnandez/lsst-centos7-make
cd lsst-centos7-make
```

**3) Build a specific version of LSST:** You must specify the version of the LSST software you want to build. For instance, to build version `v12_1` do:

```
bash runContainer.sh -t v12_1
```

This method expects the directory `/scratch` to exist in the host. This directory will be used by the `runContainer.sh` script to write the final output of the build process as well as some temporary files. Alternatively, you can use the flag `-v /path/to/host/scratch/area` to specify the work directory to use.

The LSST software built this way will is meant to be deployed via CernVM-FS under the path `/cvmfs/lsst.in2p3.fr/...`. To build the software for deployment in another directory, say `/my/deploy/top/dir`, use:

```
bash runContainer.sh  -d /my/deploy/top/dir  -t v12_1
```

**4) Build an extended version of LSST framework:** You can also build an official LSST distribution and include additional packages via the `-p` option. For instance, to build version `v12_1` and also include packages `tmv` , `galsim` and `meas_extensions_shapeHSM` do:

```
bash runContainer.sh  -p tmv,galsim,meas_extensions_shapeHSM  -t v12_1 
```

## Credits

### Author
These tools were developed and are maintained by Fabio Hernandez at [IN2P3 / CNRS computing center](http://cc.in2p3.fr) (Lyon, France).

## License
Copyright 2016 Fabio Hernandez

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.


