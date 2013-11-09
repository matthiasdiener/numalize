#!/bin/bash

set -o errexit; set -o nounset

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUTFILE=$(basename ${@}).csv

/opt/pin/pin -t $DIR/obj-intel64/*.so -- ${@} 2>$OUTFILE
