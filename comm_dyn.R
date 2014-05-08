#!/usr/bin/env Rscript

split=50

library(parallel)

options(mc.cores= as.numeric(system("grep 'processor' /proc/cpuinfo | sort | uniq | wc -l", intern=TRUE)))

files <- list.files(pattern="\\.comm\\.csv$")

read_scale = function(file) {
	if (grepl("000\\.comm\\.csv$", file)) {
		cat (file, format(Sys.time(), "%H:%M:%S"), "\n")
	}
	f = read.csv(file, header=F, quote="", colClasses="integer")
	f[f>30] = 100
	return (sum(apply(f, 1, var))/length(f))
}

het = mclapply(files, read_scale)

het_split=split(unlist(het), ceiling(seq_along(het)/split))

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

pdf("comm.pdf")


plot(unlist(het), pch=20, ylim=c(0,max(unlist(het), na.rm=T)+100))
points(seq(1, length(het_mean)*split, split), unlist(het_mean), pch=20)

garbage <- dev.off()
