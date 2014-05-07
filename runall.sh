#!/bin/bash

set -o errexit; set -o nounset


for bm in bt cg dc ep is ft lu mg sp ua; do
	for s in S W A; do
		echo $bm $s
		time ./run.sh ../nas/NPB3.3-OMP/bin/${bm}.${s}.x
	done
done

