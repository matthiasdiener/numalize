#!/usr/bin/env Rscript

# mappings:
# - first_node: place page on node that performs first access
# - local_node: put page on node with highest number of memory accesses
# - remote_node: put page on the node with the lowest number of accesses (opposite of locality)
# - rr_node: round-robin mapping of pages to nodes
# - inter_node: rr based on page address (equal to numactl -i all; uses last bits of page addr to determine node)
# - random_node: random assignment
# - mixed_node: locality for pages with high exclusivity, interleave for low excl.
# - bal_node: rr, such that number of memory accesses to all nodes are equal

options(digits=4, scipen=1000)
library(data.table)

writepages = 0 # write page mappings to csv files?

mappings = c("first_node", "local_node", "remote_node", "rr_node", "inter_node", "random_node", "mixed_node", "bal_node")

args = commandArgs(trailingOnly=T)
nargs = length(args)
if (nargs < 2)
	stop("Usage: page.R <page.csv...> <#nodes>\n")

nnodes = as.numeric(args[nargs])
files = args[1:(nargs-1)]

for (filename in files) {
	cat("##### File:", filename, "\n")
	data = read.csv(filename)

	# # for larger pages:
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
	cat("thread to node assignment:\n")
	i = 0
	for (x in n) {
		cat("\tNode ", i, ":", sprintf("%4d", x-3), "  (n=", length(x), ")\n", sep="")
		i = i+1
	}

	cat("\n\n### Properties:\n")

	for (i in 1:length(nodes))
		data[nodes[i]] = rowSums(data[unlist(n[i])])

	data = data[-threads]

	nodes = c(3:ncol(data))

	data$sum = rowSums(data[nodes])
	data$max = do.call(pmax, data[nodes])

	data$excl = data$max / data$sum * 100

	npages = nrow(data)
	total = sum(data$sum) / 100

	#### Page mappings
	data$first_node = ttn[data$firstacc+1]
	data$local_node = max.col(data[nodes], "first")

	mymin = function(x) {
		ma = which.max(x)
		mi = tail(which(x==min(x)), 1)
		mi[which.max(abs(mi-ma))]
	}
	data$remote_node = apply(data[nodes], 1, mymin)
	data$rr_node = rep(c(1:nnodes), length.out=npages)
	data$inter_node = (data$addr %% nnodes) + 1

	set.seed(1)
	data$random_node = floor(runif(npages, 1, nnodes+1))
	data$mixed_node = ifelse(data$excl > 95, data$local_node, data$rr_node)

	totaln = sum(data$sum) / nnodes
	sums = rep(0, nnodes)
	new = rep(0, npages)

	for (i in 1:npages) {
		n = data$local_node[i]

		if (sums[n] >= totaln)
			n = which.min(sums)

		new[i] = n
		sums[n] = sums[n] + data$sum[i]
	}
	data$bal_node = new


	#### Memory Balance
	cat("\nmemory balance (# pages):")
	for (map in mappings) {
		cat("\n\t", map, ":\t", sep="")
		pages = ftable(data[,map])
		cat(pages)
		cat("\t(B_Pages: ", (max(pages)/mean(pages)-1)*100, ")", sep="")
	}

	cat("\n\nmemory balance (% accesses):")
	for (map in mappings) {
		cat("\n\t", map, ":\t", sep="")
		sums = rowsum(data$sum, data[,map])/total
		cat(sprintf("%5.2f", sums))
		cat("\t(B_Acc: ", (max(sums)/mean(sums)-1)*100, ")", sep="")
	}

	#### Exclusivity
	cat("\n\npage exclusivity (rounded):\n")

	data$excl[is.na(data$excl)] = 100
	excl_min = ceiling(100/nnodes/10) * 10

	# Round exclusivity and put >, < and %
	data$excl_round = pmax(pmin(round(data$excl/10)*10, 90), excl_min)
	data$excl_round = paste(ifelse(data$excl_round==excl_min,"<",""), ifelse(data$excl_round=="90",">",""), data$excl_round, "%", sep="")

	excl = data.frame(data.table(data)[order(excl_round), sum(max), by=excl_round])
	cat("\t Rounded exclusivity\t number of accesses\n")
	cat("\t =========================\n")
	for (i in 1:nrow(excl))
		cat("\t", excl[i,1], "\t\t", excl[i,2], "\n")


	cat("\napplication exclusivity:\n\t", sum(data$max, na.rm=TRUE)/sum(data$sum, na.rm=TRUE)*100, "%\n")

	#### Locality
	cat("\nlocality (Loc_Pages, % pages):\n")
	for (map in mappings)
		cat("\t", map, ":\t", sprintf("%6.2f\n", sum((data$local_node == data[,map]))/npages*100), sep="")

	cat("\nlocality (Loc_App, % accesses):\n")
	for (map in mappings)
		cat("\t", map, ":\t", sprintf("%6.2f\n", sum((data$local_node == data[,map]) * data$sum, na.rm=TRUE)/total), sep="")

	#### Write mappings to csv files
	if (writepages) {
		cat("\n\n### Writing mappings to csv files...")
		for (map in mappings)
			write.table(data[, c("addr", map)], file=paste(filename, ".", map, sep=""), row.names=F, col.names=F)
		cat("\n\twrote", paste(filename, ".*", sep=""))
	}

	cat("\n### done.\n")
}
