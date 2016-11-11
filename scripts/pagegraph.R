#!/usr/bin/env Rscript

args = commandArgs(trailingOnly=T)
nargs = length(args)
if (nargs < 2)
	stop("Usage: page.R <page.csv...> <#nodes>\n")

nnodes = as.numeric(args[nargs])
files = args[1:(nargs-1)]

for (filename in files) {
	cat("##### File:", filename, "\n")
	data = read.csv(filename)

	outfilename = paste0(sub(".csv.*", ".excl", filename), ".png")
	outfilename2 = paste0(sub(".csv.*", ".balance", filename), ".png")

	# # for larger pages:
	# library(data.table)
	# data$addr = data$addr %/% 512
	# data = data.table(data)
	# data = data[, lapply(.SD, as.numeric)]
	# data = data[, lapply(.SD, sum), by=addr]
	# data = data.frame(data)

	threads = grep("T\\d+", names(data))
	nthreads = length(threads)
	tpn = nthreads / nnodes
	nodes = c((ncol(data)+1):(ncol(data)+nnodes))
	n = split(threads, ceiling(seq_along(threads)/tpn))
	## 0,4,2,6,1,5,3,7:
	# n=list(c(3,7), c(5,9), c(4,8), c(6,10))

	ttn=c()

	# compact thread mapping:
	for (i in 1:length(n)) ttn[n[[i]]-2] = i

	# far thread mapping:
	# ttn = rep_len(1:nnodes, nthreads)

	cat("### Input data:\n\n")
	cat("#nodes:", nnodes, "  #threads:", nthreads, "  #threads per node:", tpn, "\n\n")

	for (i in 1:length(nodes))
		data[nodes[i]] = rowSums(data[unlist(n[i])])

	data = data[-threads]

	nodes = c(3:ncol(data))

	data$sum = rowSums(data[nodes])
	data$max = do.call(pmax, data[nodes])

	data$excl = data$max / data$sum * 100
	data$first_node = ttn[data$firstacc+2]

	excl = sum(data$max)/sum(data$sum)*100


	cat("\napplication exclusivity:\n\t", sum(data$max, na.rm=TRUE)/sum(data$sum, na.rm=TRUE)*100, "%\n")


	png(outfilename, family="NimbusSan", width=2700, height=1200, res=300, type='cairo-png')
	par(mar=c(4,4,0,0)+0.1)

	plot(data$excl[data$first_node==1], data$sum[data$first_node==1], pch=20, log="y", xlab="Exclusivity (%)", ylab="Number of memory accesses", xlim=c(20,100), frame.plot = F, col=1)

	for(i in 2:nnodes)
		points(data$excl[data$first_node==i], data$sum[data$first_node==i], pch=20, col=i)

	legend(x="top", legend=paste0("N",1:nnodes), pch=20, col=c(1:nnodes))


	abline(v=excl)
	par(xpd=NA)
	text(excl, 1, sprintf("%2.2f%%",excl), adj=c(0.5,1))
	garbage = dev.off()
	cat("Generated", outfilename, "\n")

	png(outfilename2, family="NimbusSan", width=2700, height=1200, res=300, type='cairo-png')
	par(mar=c(4,4,0.2,0)+0.6, mfrow=c(1,4))

	ymax = sum(data$sum[data$first_node==1], na.rm=T)

	plot(data$excl[data$first_node==1], data$sum[data$first_node==1], pch=20, xlab="Exclusivity (%)", ylab="Number of memory accesses", log='y', frame.plot = F, col=1, xlim=c(0,100), ylim=c(1,ymax) )

	abline(h=ymax)
	par(xpd=NA)
	text(80, ymax, format(ymax,scientific=T,digits=3), pos=3)
	par(xpd=F)

	for(i in 2:nnodes) {
		plot(data$excl[data$first_node==i], data$sum[data$first_node==i], pch=20, xlab="Exclusivity (%)", ylab="", frame.plot = F,  col=1, xlim=c(0,100), log='y', ylim=c(1,ymax))
		abline(h=sum(data$sum[data$first_node==i],na.rm=T))
		par(xpd=NA)
		text(80, sum(data$sum[data$first_node==i],na.rm=T), format(sum(data$sum[data$first_node==i],na.rm=T),scientific=T,digits=3), pos=3)
		par(xpd=F)
	}

	garbage = dev.off()

	cat("Generated", outfilename2, "\n")
}
