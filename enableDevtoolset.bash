#!/bin/bash

# Usage: source enableDevtoolset.bash <devtoolset>
#    e.g. source enableDevtoolset.bash devtoolset-6

requiredSet=$1
if [[ ${requiredSet} != "" ]]; then
    sclCmd=$(command -v scl)
    if [[ ${sclCmd} != "" ]]; then
       source scl_source enable ${requiredSet}
    fi
fi
