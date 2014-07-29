#!/usr/bin/env Rscript

# missing bal_node

options(digits=4)
library(data.table)

args = commandArgs(trailingOnly=T)
if (length(args) != 2)
	stop("Usage: page.R <page.csv> <#nodes>\n")

data = read.csv(args[1])
nnodes = as.numeric(args[2])

# # for larger pages:
# data$addr = data$addr %/% 512
# data = data.table(data)
# data = data[, lapply(.SD, as.numeric)]
# data = data[, lapply(.SD, sum), by=addr]
# data = data.frame(data)

threads = grep("T\\d+", names(data))
nthreads = length(threads)
tpn = nthreads / nnodes
nodes=c((ncol(data)+1):(ncol(data)+nnodes))
n = split(threads, ceiling(seq_along(threads)/tpn))

ttn=c()
for (i in 1:length(n)) ttn[n[[i]]-3] = i

cat("### Input data:\n\n")
cat("#nodes:", nnodes, "  #threads:", nthreads, "  #threads per node:", tpn, "\n")
cat("thread to node assignment:\n")
i = 0
for (x in n) {
	cat("\tNode ", i, ":", sprintf("%5d", x-4), "\n", sep="")
	i = i+1
}

cat("\n\n### Properties:\n")

for (i in 1:length(nodes))
	data[nodes[i]] = rowSums(data[unlist(n[i])])

data = data[-threads]
data = data[-1]

nodes = c(3:ncol(data))

data$sum = rowSums(data[nodes])
data$max = do.call(pmax, data[nodes])

data$excl = data$max / data$sum * 100

npages = nrow(data)
total = sum(data$sum) / 100

#### Page mappings

data$first_touch = ttn[data$firstacc+1]
data$local_node = max.col(data[nodes], "first")
data$rr_node = rep_len(c(1:nnodes), npages)
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

#### Balance

cat("\nmemory balance (# pages):")
cat("\n\tfirst_touch:\t")
for (i in 1:nnodes)
	cat(as.integer(table(data$first_touch)[i]), "")
cat("\n\tlocal_node:\t")
for (i in 1:nnodes)
	cat(as.integer(table(data$local_node)[i]), "")
cat("\n\trr_node:\t")
for (i in 1:nnodes)
	cat(as.integer(table(data$rr_node)[i]), "")
cat("\n\tinter_node:\t")
for (i in 1:nnodes)
	cat(as.integer(table(data$inter_node)[i]), "")
cat("\n\trandom_node:\t")
for (i in 1:nnodes)
	cat(as.integer(table(data$random_node)[i]), "")
cat("\n\tmixed_node:\t")
for (i in 1:nnodes)
	cat(as.integer(table(data$mixed_node)[i]), "")
cat("\n\tbal_node:\t")
for (i in 1:nnodes)
	cat(as.integer(table(data$bal_node)[i]), "")

cat("\n\nmemory balance (% accesses):")
cat("\n\tfirst_touch:\t")
amax=0
amin=100
for (i in 1:nnodes){
	cat(sprintf("%5.2f ", sum(data$sum[data$first_touch==i], na.rm=T)/total))
	amax=max(amax, sum(data$sum[data$first_touch==i], na.rm=T)/total)
	amin=min(amin, sum(data$sum[data$first_touch==i], na.rm=T)/total)
}
cat("(", 100-(amax-amin), ")", sep="")
cat("\n\tlocal_node:\t")
amax=0
amin=100
for (i in 1:nnodes){
	cat(sprintf("%5.2f ", sum(data$sum[data$local_node==i], na.rm=T)/total))
	amax=max(amax, sum(data$sum[data$local_node==i], na.rm=T)/total)
	amin=min(amin, sum(data$sum[data$local_node==i], na.rm=T)/total)
}
cat("(", 100-(amax-amin), ")", sep="")
cat("\n\trr_node:\t")
amax=0
amin=100
for (i in 1:nnodes){
	cat(sprintf("%5.2f ", sum(data$sum[data$rr_node==i], na.rm=T)/total))
	amax=max(amax, sum(data$sum[data$rr_node==i], na.rm=T)/total)
	amin=min(amin, sum(data$sum[data$rr_node==i], na.rm=T)/total)
}
cat("(", 100-(amax-amin), ")", sep="")
cat("\n\tinter_node:\t")
amax=0
amin=100
for (i in 1:nnodes){
	cat(sprintf("%5.2f ", sum(data$sum[data$inter_node==i], na.rm=T)/total))
	amax=max(amax, sum(data$sum[data$inter_node==i], na.rm=T)/total)
	amin=min(amin, sum(data$sum[data$inter_node==i], na.rm=T)/total)
}
cat("(", 100-(amax-amin), ")", sep="")
cat("\n\trandom_node:\t")
amax=0
amin=100
for (i in 1:nnodes){
	cat(sprintf("%5.2f ", sum(data$sum[data$random_node==i], na.rm=T)/total))
	amax=max(amax, sum(data$sum[data$random_node==i], na.rm=T)/total)
	amin=min(amin, sum(data$sum[data$random_node==i], na.rm=T)/total)
}
cat("(", 100-(amax-amin), ")", sep="")
cat("\n\tmixed_node:\t")
amax=0
amin=100
for (i in 1:nnodes){
	cat(sprintf("%5.2f ", sum(data$sum[data$mixed_node==i], na.rm=T)/total))
	amax=max(amax, sum(data$sum[data$mixed_node==i], na.rm=T)/total)
	amin=min(amin, sum(data$sum[data$mixed_node==i], na.rm=T)/total)
}
cat("(", 100-(amax-amin), ")", sep="")
cat("\n\tbal_node:\t")
amax=0
amin=100
for (i in 1:nnodes){
	cat(sprintf("%5.2f ", sum(data$sum[data$bal_node==i], na.rm=T)/total))
	amax=max(amax, sum(data$sum[data$bal_node==i], na.rm=T)/total)
	amin=min(amin, sum(data$sum[data$bal_node==i], na.rm=T)/total)
}
cat("(", 100-(amax-amin), ")", sep="")


#### Exclusivity
cat("\n\npage exclusivity (rounded):\n")

data$excl[is.na(data$excl)] = 100
excl_min = ceiling(100/nnodes/10) * 10

# Round exclusivity and put >, < and %
data$excl_round = pmax(pmin(round(data$excl/10)*10, 90), excl_min)
data$excl_round = paste(ifelse(data$excl_round==excl_min,"<",""), ifelse(data$excl_round=="90",">",""), data$excl_round, "%", sep="")

excl = data.frame(data.table(data)[order(excl_round), sum(max), by=excl_round])
cat("\t excl_round\t #accesses\n")
cat("\t =========================\n")
for (i in 1:nrow(excl))
	cat("\t", excl[i,1], "\t\t", excl[i,2], "\n")


cat("\napplication exclusivity:\n\t", sum(data$max, na.rm=TRUE)/sum(data$sum, na.rm=TRUE)*100, "%\n")

#### Accuracy

cat("\naccuracy (% pages):\n")

cat("\tfirst_touch:\t", sprintf("%6.2f\n", sum((data$local_node == data$first_touch))/npages*100))
cat("\tlocal_node:\t", sprintf("%6.2f\n", sum((data$local_node == data$local_node))/npages*100))
cat("\trr_node:\t", sprintf("%6.2f\n", sum((data$rr_node == data$local_node))/npages*100))
cat("\tinter_node:\t", sprintf("%6.2f\n", sum((data$inter_node == data$local_node))/npages*100))
cat("\trandom_node:\t", sprintf("%6.2f\n", sum((data$random_node == data$local_node))/npages*100))
cat("\tmixed_node:\t", sprintf("%6.2f\n", sum((data$mixed_node == data$local_node))/npages*100))
cat("\tbal_node:\t", sprintf("%6.2f\n", sum((data$bal_node == data$local_node))/npages*100))

cat("\naccuracy (% accesses):\n")

cat("\tfirst_touch:\t", sprintf("%6.2f\n", sum((data$local_node == data$first_touch) * data$sum, na.rm=TRUE)/total))
cat("\tlocal_node:\t", sprintf("%6.2f\n", sum((data$local_node == data$local_node) * data$sum, na.rm=TRUE)/total))
cat("\trr_node:\t", sprintf("%6.2f\n", sum((data$local_node == data$rr_node) * data$sum, na.rm=TRUE)/total))
cat("\tinter_node:\t", sprintf("%6.2f\n", sum((data$local_node == data$inter_node) * data$sum, na.rm=TRUE)/total))
cat("\trandom_node:\t", sprintf("%6.2f\n", sum((data$local_node == data$random_node) * data$sum, na.rm=TRUE)/total))
cat("\tmixed_node:\t", sprintf("%6.2f\n", sum((data$local_node == data$mixed_node) * data$sum, na.rm=TRUE)/total))
cat("\tbal_node:\t", sprintf("%6.2f\n", sum((data$local_node == data$bal_node) * data$sum, na.rm=TRUE)/total))
