#!/bin/bash

set -o errexit; set -o nounset

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

(cd $DIR; make)


OUTFILE=$(basename ${1}).csv

time -p /opt/pin/pin -t $DIR/obj-intel64/*.so -- ${@}
# pigz --best $OUTFILE

# echo "created $OUTFILE.gz"
