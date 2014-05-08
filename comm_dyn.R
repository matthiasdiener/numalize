#!/usr/bin/env Rscript

split=500

library(parallel)

options(mc.cores=as.numeric(system("grep 'processor' /proc/cpuinfo | sort | uniq | wc -l", intern=TRUE)))

files <- list.files(pattern="\\.comm\\.csv$")

read_het_avg = function(file) {
	if (grepl("000\\.comm\\.csv$", file)) {
		cat ("Reading", file, format(Sys.time(), "%H:%M:%S"), "\n")
	}
	f = read.csv(file, header=F, quote="", colClasses="integer")
	f[f>30] = 100
	return(list(het=sum(apply(f, 1, var))/length(f), avg=sum(as.numeric(unlist(f)))/length(f) ))
}

res = mclapply(files, read_het_avg)
het = unlist(res)[attr(unlist(res),"names")=="het"]
avg = unlist(res)[attr(unlist(res),"names")=="avg"]

het_split = split(unlist(het), ceiling(seq_along(het)/split))
avg_split = split(unlist(avg), ceiling(seq_along(avg)/split))

het_mean = mclapply(het_split, mean)
avg_mean = mclapply(avg_split, mean)

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

write.csv(data.frame(het, avg), "comm_dyn.csv")

png("comm_dyn.png", width=960, res=100)

plot(unlist(het), pch=".", ylim=c(0,max(unlist(het),unlist(avg), na.rm=T)+100), xlab="Time", ylab="Het / Avg", col="gray")
points(seq(1, length(het_mean)*split, split), unlist(het_mean), pch=20, col="black")

points(unlist(avg), pch=".", col="lightgreen")
points(seq(1, length(avg_mean)*split, split), unlist(avg_mean), pch=20, col="green")

garbage <- dev.off()
