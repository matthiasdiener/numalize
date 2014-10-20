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
OUTFILE=$PROG.gdbstackmap

PAGESIZE=$(getconf PAGESIZE)

echo "Gathering stack information via gdb"

rm -f gdb.txt

cat > stack.gdb << EOF
	python import os, math
	python pagebits=int(math.log($PAGESIZE, 2))
	python fname = os.path.basename(gdb.objfiles()[0].filename)
	python f = open(fname + ".gdbstackmap", 'w')
	python f2 = open(fname + ".gdbstackmap2", 'w')

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

	break exit
	commands 3
		python for x in gdb.inferiors()[0].threads(): id=x.num; print(id); gdb.execute("thread " + str(id)); print(id-1, int(gdb.parse_and_eval('\$rsp')) >> pagebits, file=f2)
		continue
	end

	run

	# python f.close()
	# python f2.close()

EOF

gdb --batch --command=stack.gdb --args $PROGARGS

# exit
# n=0
# cat gdb.txt | grep '^$.*=' | tac | cut -f 3 -d ' ' | while read line; do  echo $line/$PAGESIZE | bc | sed -e s,^,$n\ , ; n=$((n+1)) ; done | tee $OUTFILE

# rm -f gdb.txt

cat $OUTFILE
exit
echo -e "\n\nRunning pin"

time -p pin -xyzzy -enable_vsm 0 -t $DIR/obj-*/*.so ${@}

rm -f $OUTFILE

for f in $PROG.*.page.csv; do
	sort -n -t, -k 1,1 -o $f $f
done
