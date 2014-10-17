#!/bin/bash

set -o errexit; set -o nounset

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

VA_RANDOM=$(sysctl -n kernel.randomize_va_space)
if [ $VA_RANDOM -eq 0 ]; then
	echo; echo "WARNING"
	echo "sysctl kernel.randomize_va_space needs to be 0 (is $VA_RANDOM currently)"
	echo "Generated information will be incorrect"
	echo "WARNING"; echo
fi

(cd $DIR; make -q || make)

PROGARGS=$(echo ${@} | sed s,.*--\ ,,)
PROG=$(echo $PROGARGS | { read first rest; echo $(basename $first) | sed s,\\s.*,, ; } )
OUTFILE=$PROG.stackmap

PAGESIZE=$(getconf PAGESIZE)

cat > stack.gdb << EOF
	break exit

	run

	thread apply all print/u \$rsp
	continue
EOF

echo "Gathering stack information via gdb"

n=0

gdb --batch --command=stack.gdb --args $PROGARGS | grep '^$.*=' | tac | cut -f 3 -d ' ' | while read line; do  echo $line/$PAGESIZE | bc | sed -e s,^,$n\ , ; n=$((n+1)) ; done > $OUTFILE


rm -f stack.gdb

echo "Running pin"

time -p pin -xyzzy -enable_vsm 0 -t $DIR/obj-*/*.so ${@}

rm -f $OUTFILE

for f in $PROG.*.page.csv; do
	sort -n -t, -k 1,1 -o $f $f
done
