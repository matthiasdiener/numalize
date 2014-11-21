#!/bin/bash

set -o errexit; set -o nounset

# directory of run.sh
DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# randomizing the virtual address space needs to be off for correct traces
VA_RANDOM=$(sysctl -n kernel.randomize_va_space)
if [ $VA_RANDOM -ne 0 ]; then
	echo; echo "WARNING WARNING WARNING"
	echo "sysctl kernel.randomize_va_space needs to be 0 (it is $VA_RANDOM currently)"
	echo "Generated information will be incorrect"
	echo "WARNING WARNING WARNING"; echo
fi

# recompile pintool if necessary
(cd $DIR; make -q || make)

PROGARGS=$(echo ${@} | sed s,.*--\ ,,)
PROG=$(echo $PROGARGS | { read first rest; echo $(basename $first) | sed s,\\s.*,, ; } )
OUTFILE=$PROG.stackmap

PAGESIZE=$(getconf PAGESIZE)

echo -e "## gathering stack information via gdb\n"

cat > stack.gdb << EOF
	python import os, math, subprocess, sys
	python pagebits = int(math.log($PAGESIZE, 2))
	python f = open("$OUTFILE", 'w')
	# python f2 = open("$OUTFILE" + "2", 'w')
	python stack = [0,0,0,0,0,0,0,0,0,0,0]

	# for Pthreads programs:
	catch syscall exit
	catch syscall exit_group
	# catch syscall clone

	commands 1-2
python

# ppid = gdb.selected_inferior().pid
# pid = gdb.selected_thread().ptid[1]
# tid = gdb.selected_thread().num - 1
# line = subprocess.Popen("cat /proc/" + str(ppid) + "/maps | grep " + str(pid) + " | cut -f 1 -d ' '", shell=True, stdout=subprocess.PIPE).stdout.read().decode("utf-8")
# print(ppid, tid, pid, file=sys.stderr)
# min, max = line.split("-", 2)
# print(min, max, file=sys.stderr)

end
continue
	end

catch syscall clone
commands 3
python
ppid = gdb.selected_inferior().pid
if stack[0] == 0:
	line = subprocess.Popen("cat /proc/" + str(ppid) + "/maps | grep stack | cut -f 1 -d ' '", shell=True, stdout=subprocess.PIPE).stdout.read().decode("utf-8")
	if line:
		min, max = line.split("-", 2)
		print(0, ppid, min, max, file=sys.stderr)
		stack[0] = 1

for t in gdb.selected_inferior().threads():
	tid = t.num - 1
	pid = t.ptid[1]
	if stack[tid] != 0:
		continue
	line = subprocess.Popen("cat /proc/" + str(ppid) + "/maps | grep " + str(pid) + " | cut -f 1 -d ' '", shell=True, stdout=subprocess.PIPE).stdout.read().decode("utf-8")

	if line:
		min, max = line.split("-", 2)
		print(tid, pid, min, max, file=sys.stderr)
		stack[tid] = 1
end
continue
end
	run

	python f.close()
	# python f2.close()
EOF

# run gdb with stack script
gdb --batch-silent --command=stack.gdb --args $PROGARGS

rm -f stack.gdb

exit

sort -n -k 1,1 -o $OUTFILE $OUTFILE
sort -n -k 1,1 -o ${OUTFILE}2 ${OUTFILE}2

LEN1=$(wc -l $OUTFILE | cut -f 1 -d ' ')
LEN2=$(wc -l ${OUTFILE}2 | cut -f 1 -d ' ')

if [[ $LEN1 -gt $LEN2 ]]; then
	echo -e "\n# chose $OUTFILE (pthreads)"
	cat $OUTFILE
else
	echo -e "\n# chose ${OUTFILE}2 (openmp)"
	cat ${OUTFILE}2
	mv ${OUTFILE}2 ${OUTFILE}
fi


# finally, run pin
echo -e "\n\n## running pin"

time -p pin -xyzzy -enable_vsm 0 -t $DIR/obj-*/*.so ${@}

rm -f $OUTFILE ${OUTFILE}2


# sort output page csv according to page address
for f in $PROG.*.page.csv; do
	sort -n -t, -k 1,1 -o $f $f
done
