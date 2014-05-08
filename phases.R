#!/usr/bin/env Rscript

library(parallel)

options(mc.cores= as.numeric(system("grep 'processor' /proc/cpuinfo | sort | uniq | wc -l", intern=TRUE)))

files <- list.files(pattern="\\.comm\\.csv$")

read_scale = function(x) {
	if (grepl("000\\.comm\\.csv$", x))
		cat (x, "\n")
	f = read.csv(x, header=F, quote="", colClasses="integer")
	f[f>30] = 100
	return (sum(apply(f, 1, var))/length(f))
}

het = mclapply(files, read_scale)

het_split=split(unlist(het), ceiling(seq_along(het)/50))

het_mean = lapply(het_split, mean)

xold=0
n=0

for (x in het_mean) {
	cat(x, " ")
	if (is.na(x)) next
	if (findInterval(x, c(xold/1.2, xold*1.2)) == 0){
		cat("new phase ")
		n=n+1
	}
	xold=x

}
cat ("\nn=", n, "\n")
