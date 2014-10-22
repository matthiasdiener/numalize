#!/bin/bash

set -o errexit; set -o nounset

DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

VA_RANDOM=$(sysctl -n kernel.randomize_va_space)
if [ $VA_RANDOM -ne 0 ]; then
	echo; echo "WARNING"
	echo "sysctl kernel.randomize_va_space needs to be 0 (it is $VA_RANDOM currently)"
	echo "Generated information will be incorrect"
	echo "WARNING"; echo
fi

(cd $DIR; make -q || make)

PROGARGS=$(echo ${@} | sed s,.*--\ ,,)
PROG=$(echo $PROGARGS | { read first rest; echo $(basename $first) | sed s,\\s.*,, ; } )
OUTFILE=$PROG.stackmap

PAGESIZE=$(getconf PAGESIZE)

echo "Gathering stack information via gdb"

rm -f gdb.txt

cat > stack.gdb << EOF
	python import os, math
	python pagebits = int(math.log($PAGESIZE, 2))
	python f = open("$OUTFILE", 'w')
	python f2 = open("$OUTFILE" + "2", 'w')

	# for Pthreads programs:
	catch syscall exit
	commands 1
		python print(gdb.selected_thread().num-1, int(gdb.parse_and_eval('\$rsp')) >> pagebits, file=f)
		continue
	end

	catch syscall exit_group
	commands 2
		python print(gdb.selected_thread().num-1, int(gdb.parse_and_eval('\$rsp')) >> pagebits, file=f)
		continue
	end

	# for OpenMP programs:
	break exit
	commands 3
		python for x in gdb.inferiors()[0].threads(): id=x.num; print(id); gdb.execute("thread " + str(id)); print(id-1, int(gdb.parse_and_eval('\$rsp')) >> pagebits, file=f2)
		continue
	end

	run

	python f.close()
	python f2.close()
EOF

gdb --batch-silent --command=stack.gdb --args $PROGARGS

rm -f stack.gdb

sort -n -k 1,1 -o $OUTFILE $OUTFILE
sort -n -k 1,1 -o ${OUTFILE}2 ${OUTFILE}2

LEN1=$(wc -l $OUTFILE | cut -f 1 -d ' ')
LEN2=$(wc -l ${OUTFILE}2 | cut -f 1 -d ' ')

if [[ $LEN1 -gt $LEN2 ]]; then
	echo "would choose $OUTFILE"
	cat $OUTFILE
else
	echo "would choose ${OUTFILE}2"
	cat ${OUTFILE}2
	mv ${OUTFILE}2 ${OUTFILE}
fi


# exit
echo -e "\n\nRunning pin"

time -p pin -xyzzy -enable_vsm 0 -t $DIR/obj-*/*.so ${@}

rm -f $OUTFILE ${OUTFILE}2

for f in $PROG.*.page.csv; do
	sort -n -t, -k 1,1 -o $f $f
done
