#!/usr/bin/env Rscript

library(parallel)

fs <- list.files(pattern="\\.comm\\.csv$")

read_scale = function(x) {
	f = read.csv(x, header=F, quote="", colClasses="integer")
	f[f>30] = 100
	return (sum(apply(f, 1, var))/length(f))
}

l = mclapply(fs, read_scale, mc.cores=4)

xx=split(unlist(l), ceiling(seq_along(l)/50))


m=c()

for (x in xx)
	m=append(m, mean(x))

xold=0
n=0
for (x in m) {
	print(x)
	if (is.na(x)) next
	if (findInterval(x, c(xold/1.2, xold*1.2)) == 0){

		print("new phase")
		n=n+1
	}
	xold=x

}
cat ("n= ", n, "\n")
