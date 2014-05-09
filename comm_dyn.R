#!/usr/bin/env Rscript

split=500
files = list.files(pattern="\\.comm\\.csv$")

args <- commandArgs(trailingOnly=TRUE)
if (length(args) > 0)
	files = args

library(parallel)
options(mc.cores=max(as.numeric(system("grep 'processor' /proc/cpuinfo | sort | uniq | wc -l", intern=TRUE)), 4) )


comm_het = function(frame) {
	frame = frame / max(frame, na.rm=T) * 100
	frame[frame>30] = 100
	return(mean(apply(frame, 1, var, na.rm=T)))
}

comm_avg = function(frame)
	return(sum(as.numeric(unlist(frame)))/length(frame)/length(frame))


read_het_avg = function(file) {
	f = read.csv(file, header=F, quote="", colClasses="integer")

	if (grepl("000\\.comm\\.csv$", file))
		cat ("Reading", file, " #threads", length(f), format(Sys.time(), " %H:%M:%S"), "\n")

	return(list(het=comm_het(f), avg=comm_avg(f) ))
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

png("comm_dyn.png", width=1920, res=100)

plot(unlist(het), pch=".", ylim=c(0,max(unlist(het),unlist(avg), na.rm=T)+100), xlab="Time", ylab="Het / Avg", col="gray", xlim=c(-5,length(het)))
# points(seq(1, length(het_mean)*split, split), unlist(het_mean), pch=20, col="black")

points(unlist(avg), pch=".", col="lightgreen")
# points(seq(1, length(avg_mean)*split, split), unlist(avg_mean), pch=20, col="green")

garbage <- dev.off()
