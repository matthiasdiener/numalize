#!/bin/bash

set -o errexit; set -o nounset

# directory of run.sh
DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# randomizing the virtual address space needs to be off for correct traces
VA_RANDOM=$(sysctl -n kernel.randomize_va_space)
if [ $VA_RANDOM -ne 0 ]; then
	echo "sysctl kernel.randomize_va_space needs to be 0 for a correct trace (it is $VA_RANDOM currently)"
	echo "exiting"
	exit 1
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
	python stack = [0 for i in range(1024)]


catch syscall clone
commands 1
python
ppid = gdb.selected_inferior().pid
if stack[0] == 0:
	line = subprocess.Popen("cat /proc/" + str(ppid) + "/maps | grep '\[stack\]' | cut -f 1 -d ' '", shell=True, stdout=subprocess.PIPE).stdout.read().decode("utf-8")
	if line:
		min, max = line.split("-", 2)
		min = int(min, 16) >> pagebits
		max = int(max, 16) >> pagebits
		# print(0, ppid, min, max, max-min, file=sys.stderr)
		stack[0] = (min,max)

for t in gdb.selected_inferior().threads():
	tid = t.num - 1
	pid = t.ptid[1]
	if stack[tid] != 0:
		continue
	line = subprocess.Popen("cat /proc/" + str(ppid) + "/maps | grep '\[stack:" + str(pid) + "\]' | cut -f 1 -d ' '", shell=True, stdout=subprocess.PIPE).stdout.read().decode("utf-8")

	if line:
		min, max = line.split("-", 2)
		min = int(min, 16) >> pagebits
		max = int(max, 16) >> pagebits
		# print(tid, pid, min, max, max-min, file=sys.stderr)
		stack[tid] = (min,max)
end
continue
end
	run

	python
i=-1
for t in stack:
	i=i+1
	if t!=0:
		# print (i, t, file=sys.stderr)
		print (i, t[1], file=f)
f.close()
end
EOF

# run gdb with stack script
gdb --batch-silent --command=stack.gdb --args $PROGARGS

rm -f stack.gdb


# finally, run pin
echo -e "\n\n## running pin"

time -p pin -xyzzy -enable_vsm 0 -t $DIR/obj-*/*.so ${@}

# rm -f $OUTFILE ${OUTFILE}2


# sort output page csv according to page address
for f in $PROG.*.page.csv; do
	sort -n -t, -k 1,1 -o $f $f
done
