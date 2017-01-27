#!/usr/bin/env Rscript

# mappings:
# - first: put page on the node that performs first access
# - local: put page on the node with highest number of memory accesses
# - remote: put page on the node with the lowest number of accesses (opposite of locality)
# - rr: round-robin mapping of pages to nodes
# - inter: rr based on page address (equal to numactl -i all; uses last bits of page addr to determine node)
# - random: random assignment of pages to nodes
# - mixed: locality for pages with high exclusivity, interleave for low exclusivity
# - balance: distribute pages such that the number of memory accesses to all nodes are equal


options(digits=4, scipen=1000, warn=2)
library(data.table)
library(optparse)

option_list <- list(
    make_option(c("-t","--write_table"), action="store_true", default=FALSE, help="Write csv table file with page usage [default %default]"),
    make_option(c("-n", "--nnodes"), type="integer", default=4, help="Number of NUMA nodes [default %default]"),
    make_option(c("-w", "--write_pages"), action="store_true", default=FALSE, help="Write page mapping files [default %default]")
)

arguments = parse_args(OptionParser(usage = "%prog [options] files",option_list=option_list), positional_arguments = TRUE)
opt = arguments$options
files = arguments$args

nnodes = opt$nnodes

mappings = c("first","local","remote","rr","inter","random","mixed","balance")

pagesizes = c(1:20)
r_excl = seq(0,100,10)

res_names = c("App","excl.default", paste0("excl.", pagesizes), paste0("roundedexcl.", r_excl))

for (map in mappings)
	res_names = c(res_names, paste0(map, ".locpages"))

for (map in mappings)
	res_names = c(res_names, paste0(map, ".locapp"))

for (map in mappings) {
	res_names = c(res_names, paste0(map, ".bpages"))
	res_names = c(res_names, paste0(map, ".bpages.N", c(1:nnodes)))
}

for (map in mappings) {
	res_names = c(res_names, paste0(map, ".bacc"))
	res_names = c(res_names, paste0(map, ".bacc.N", c(1:nnodes)))
}

result = read.table(text="", col.names = res_names)

for (filename in files) {
	cat("##### File:", filename, "\n")
	data = read.csv(filename)
	bench = sub("\\..*", "", basename(filename))
	bench = ifelse(nchar(bench)<3, toupper(bench), paste0(toupper(substring(bench,1,1)),substring(bench,2,1000)))

	res = c(bench)

	threads = grep("T\\d+", names(data))
	nthreads = length(threads)
	tpn = nthreads / nnodes
	nodes = c((ncol(data)+1):(ncol(data)+nnodes))
	n = split(threads, ceiling(seq_along(threads)/tpn))
	## 0,4,2,6,1,5,3,7:
	# n=list(c(3,7), c(5,9), c(4,8), c(6,10))

	ttn = c()

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
	data$excl[is.na(data$excl)] = 100
	data$firstacc[data$firstacc>=nthreads] = nthreads-1

	npages = nrow(data)
	total = sum(data$sum) / 100

	#### Page mappings
	data$first = ttn[data$firstacc+1]
	data$local = max.col(data[nodes], "first")

	mymin = function(x) {
		ma = which.max(x)
		mi = tail(which(x==min(x)), 1)
		mi[which.max(abs(mi-ma))]
	}
	data$remote = apply(data[nodes], 1, mymin)
	data$rr = rep(c(1:nnodes), length.out=npages)
	data$inter = (data$addr %% nnodes) + 1

	set.seed(1)
	data$random = floor(runif(npages, 1, nnodes+1))
	data$mixed = ifelse(data$excl > 95, data$local, data$rr)

	totaln = sum(data$sum) / nnodes
	sums = rep(0, nnodes)
	new = rep(0, npages)

	for (i in 1:npages) {
		n = data$local[i]

		if (sums[n] >= totaln)
			n = which.min(sums)

		new[i] = n
		sums[n] = sums[n] + data$sum[i]
	}
	data$balance = new

	#### Exclusivity
	excl = sum(data$max)/sum(data$sum)*100

	cat("\nApplication exclusivity (Excl_App):\n\t", excl, "%\n")
	res = c(res, excl)

	# for larger pages:
	new = data
	for (i in pagesizes) {
		new$addr = new$addr %/% 2
		new = data.table(new)
		new = new[, lapply(.SD, sum), by=addr]
		new = data.frame(new)
		new$sum = rowSums(new[nodes])
		new$max = do.call(pmax, new[nodes])
		excl = sum(new$max)/sum(new$sum)*100
		res = c(res, excl)
	}

	cat("\n\nPage exclusivity (rounded):\n")

	excl_min = ceiling(100/nnodes/10) * 10

	# Round exclusivity
	data$excl_round = round(data$excl/10)*10
	excl = merge(data.frame(Group.1=r_excl), aggregate(data$sum, FUN=sum, by=list(data$excl_round)), all=T)
	excl[is.na(excl)] = 0

	cat("\tRounded exclusivity\tNumber of accesses\n")
	cat("\t==========================================\n")
	for (i in 1:nrow(excl))
		cat("\t", excl[i,1], "%\t\t\t", excl[i,2], "\n", sep="")
	res = c(res, excl[,2])

	#### Locality
	cat("\nLocality (Loc_Pages, % pages):\n")
	for (map in mappings) {
		val = sum((data$local == data[,map]))/npages*100
		cat("\t", map, ":     \t", sprintf("%6.2f\n", val), sep="")
		res = c(res, val)
	}

	cat("\nLocality (Loc_App, % accesses):\n")
	for (map in mappings) {
		val = sum((data$local == data[,map]) * data$sum)/total
		cat("\t", map, ":     \t", sprintf("%6.2f\n", val), sep="")
		res = c(res, val)
	}

	#### Memory Balance
	cat("\nMemory balance (B_Pages, # pages):")
	for (map in mappings) {
		cat("\n\t", map, ":     \t", sep="")
		pages = tabulate(data[,map], nnodes)
		bpages = (max(pages)/mean(pages)-1) * 100
		cat(pages)
		cat("\t(B_Pages: ", bpages, ")", sep="")
		res = c(res, bpages, pages)
	}

	cat("\n\nMemory balance (B_Acc, % accesses):")
	for (map in mappings) {
		cat("\n\t", map, ":     \t", sep="")
		sums = c()
		for (n in 1:nnodes)
			sums = c(sums, sum(data$sum[data[,map]==n])/total)
		bacc = (max(sums)/mean(sums)-1) * 100
		cat(sprintf("%5.2f", sums))
		cat("\t(B_Acc: ", bacc, ")", sep="")
		res = c(res, bacc, sums)
	}

	#### Write mappings to csv files
	if (opt$write_pages) {
		cat("\n\n### Writing mappings to csv files...")
		for (map in mappings)
			write.table(data[, c("addr", map)], file=paste0(filename, ".", map), row.names=F, col.names=F)
		cat("\n\twrote", paste(filename, ".*", sep=""))
	}

	result[nrow(result)+1,] = res
	cat("\n### Done.\n")
}

cols = c(2:ncol(result))
result[,cols] = as.numeric(as.character(unlist(result[,cols])))

if (opt$write_table) {
	outfilename = paste0(dirname(files[1]), "/pageusage_",nnodes,"N.csv")
	write.table(format(result, digits=4), file=outfilename, row.names=F, quote=F, sep=",")
	cat("# Files:", files, "\n", file=outfilename, append=TRUE)
	cat("# Nodes:", nnodes, "\n", file=outfilename, append=TRUE)
	cat("### Wrote", outfilename, "\n")
}
