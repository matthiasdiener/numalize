#!/bin/bash

set -o errexit -o nounset -o pipefail

# directory of this script
DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# recompile pintool if necessary
(cd $DIR; make -q || make)

# program to trace and its arguments
PROGARGS=$(echo ${@} | sed s,.*--\ ,,)
PROG=$(echo $PROGARGS | { read first rest; echo $(basename $first) | sed s,\\s.*,, ; } )

# Run pin
echo "### running pin: $PROGARGS"

time -p pin -xyzzy -enable_vsm 0 -t $DIR/obj-*/*.so ${@}

if [[ $1 == "-p" ]]; then
	# sort output page csv's according to page address
	for f in $PROG.*.page.csv; do
		sort -n -t, -k 1,1 -o $f $f
	done
fi
