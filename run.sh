#!/bin/bash

set -o errexit; set -o nounset

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

(cd $DIR; make -q || make)

PROGARGS=$(echo ${@} | sed s,.*--\ ,,)
OUTFILE=$(basename $PROGARGS | sed s,\\s.*,,).stackmap

PAGE_SHIFT=$(echo l\($(getconf PAGESIZE)\)/l\(2\) | bc -l | sed s,\\..*,,)

cat > stack.gdb << EOF
	break exit

	run

	thread apply all print (unsigned long)\$rsp >> $PAGE_SHIFT
	continue
EOF

n=-1

gdb --batch --command=stack.gdb --args $PROGARGS | grep = | tac | cut -f 3 -d ' ' | while read line; do n=$((++n)) &&  echo $line|sed -e s,^,$n\ , ; done > $OUTFILE

echo real stack
cat $OUTFILE
echo

rm -f stack.gdb

pin -t $DIR/obj-*/*.so ${@}

rm -f $OUTFILE
